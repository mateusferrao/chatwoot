# Mantém o db/schema.rb coerente com as migrations próprias do fork, listadas em
# ops/upstream-sync/fork-migrations.txt.
#
# Por que existe: em banco novo, a produção (db:chatwoot_prepare) carrega o
# db/schema.rb e o Schema.define dá como rodadas todas as migrations com versão até
# a do schema. Se uma tabela do fork sumir do schema.rb (ex.: num merge do
# upstream), ela nunca seria criada.
#
# - regenerate!: carrega o schema.rb do upstream num banco descartável e faz o dump
#   antes e depois de aplicar as migrations do fork. A diferença entre os dois dumps
#   (tabelas do fork, chaves estrangeiras e versão) é aplicada sobre o texto do
#   schema.rb do upstream com um merge de três vias (git merge-file), para o diff
#   contra o upstream mostrar só o que é do fork, sem as diferenças de formatação
#   entre o dumper do Rails/Postgres local e o que o upstream usou. O resultado é
#   conferido: carregado num banco limpo, precisa gerar o mesmo dump.
#   (ops/scripts/regenerate-fork-schema.sh)
# - check!: carrega o db/schema.rb num banco descartável, desfaz e refaz as
#   migrations do fork e exige que o dump continue idêntico. Tabela ou coluna do
#   fork ausente faz o "desfazer" falhar; estrutura diferente muda o dump.
#   (ops/scripts/check-fork-schema.sh)
#
# Os bancos descartáveis usam a configuração do ambiente atual com o nome
# "<prefixo>_sync_<pid>" e são apagados ao final, mesmo em caso de erro.
# Migrations rodam pela mesma API dos tasks db:migrate:up/down
# (MigrationContext#run), sem o dump automático do db/schema.rb que esses tasks fazem.
require 'open3'
require 'tmpdir'

class Fork::SchemaSync
  MANIFEST_PATH = 'ops/upstream-sync/fork-migrations.txt'.freeze
  FORK_MIGRATIONS_GLOB = 'db/migrate/*automato_agents*.rb'.freeze
  SCHEMA_HEADER = /ActiveRecord::Schema\[\d+\.\d+\]/

  class Error < StandardError; end

  def initialize(root: Rails.root)
    @root = Pathname(root)
  end

  # Grava o schema regenerado em output. Retorna :merged (diff mínimo contra o upstream)
  # ou :full_dump (o merge de três vias conflitou; gravou o dump completo, que é correto
  # mas traz as diferenças de formatação do dumper local).
  def regenerate!(upstream_schema:, output:)
    validate_manifest!
    upstream = File.read(upstream_schema)
    header = upstream[SCHEMA_HEADER] || raise(Error, "cabeçalho ActiveRecord::Schema[x.y] não encontrado em #{upstream_schema}")

    upstream_dump, fork_dump = dumps_before_and_after_fork_migrations(upstream_schema, header)
    merged = merge_onto_upstream(upstream, upstream_dump, fork_dump)
    File.write(output, merged || fork_dump)
    ensure_loads_as!(output, fork_dump, header)
    merged ? :merged : :full_dump
  end

  def check!(schema:)
    validate_manifest!

    with_scratch_database('chatwoot_schema_check') do
      load_schema(schema)
      ensure_fork_versions_recorded!
      loaded = dump
      fork_versions.reverse_each { |version| revert!(version) }
      fork_versions.each { |version| pool.migration_context.run(:up, version) }
      ensure_same_dump!(loaded, dump)
    end
  end

  private

  def fork_migrations
    @fork_migrations ||= File.readlines(@root.join(MANIFEST_PATH), chomp: true)
                             .map(&:strip)
                             .reject { |line| line.empty? || line.start_with?('#') }
  end

  def fork_versions
    @fork_versions ||= fork_migrations.map { |path| File.basename(path)[/\A\d+/].to_i }.sort
  end

  def validate_manifest!
    problems = fork_migrations.reject { |path| path.match?(%r{\Adb/migrate/\d+_\w+\.rb\z}) && @root.join(path).file? }
                              .map { |path| "listada em #{MANIFEST_PATH}, mas não existe (ou não está em db/migrate/<versão>_<nome>.rb): #{path}" }

    unlisted = Dir.glob(FORK_MIGRATIONS_GLOB, base: @root).sort - fork_migrations
    problems += unlisted.map { |path| "migration do fork fora de #{MANIFEST_PATH} (adicione-a lá): #{path}" }

    raise Error, problems.join("\n") if problems.any?
  end

  def dumps_before_and_after_fork_migrations(upstream_schema, header)
    with_scratch_database('chatwoot_schema_regen') do
      load_schema(upstream_schema)
      before = dump
      fork_versions.each do |version|
        # O Schema.define do upstream dá como rodadas as migrations com versão menor que a
        # dele, inclusive as do fork; desmarca para aplicá-las de verdade.
        pool.schema_migration.delete_version(version.to_s)
        pool.migration_context.run(:up, version)
      end
      [before, dump].map { |text| text.sub(SCHEMA_HEADER, header) }
    end
  end

  def with_scratch_database(prefix)
    original = ActiveRecord::Base.connection_db_config
    scratch = ActiveRecord::DatabaseConfigurations::HashConfig.new(
      original.env_name, original.name, original.configuration_hash.merge(database: "#{prefix}_sync_#{Process.pid}")
    )
    verbose_was = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = ENV['VERBOSE'].present?
    ActiveRecord::Tasks::DatabaseTasks.create(scratch)
    begin
      ActiveRecord::Base.establish_connection(scratch)
      yield
    ensure
      ActiveRecord::Tasks::DatabaseTasks.drop(scratch)
      ActiveRecord::Base.establish_connection(original)
      ActiveRecord::Migration.verbose = verbose_was
    end
  end

  def pool
    ActiveRecord::Base.connection_pool
  end

  def load_schema(schema_path)
    ActiveRecord::Tasks::DatabaseTasks.load_schema(ActiveRecord::Base.connection_db_config, :ruby, schema_path.to_s)
  end

  def dump
    ActiveRecord::SchemaDumper.dump(pool, StringIO.new).string
  end

  # Aplica a mudança upstream_dump -> fork_dump sobre o texto do upstream. nil se conflitar.
  def merge_onto_upstream(upstream, upstream_dump, fork_dump)
    Dir.mktmpdir do |dir|
      paths = { upstream: upstream, upstream_dump: upstream_dump, fork_dump: fork_dump }.to_h do |name, text|
        path = File.join(dir, "#{name}.rb")
        File.write(path, text)
        [name, path]
      end
      merged, status = Open3.capture2('git', 'merge-file', '-p', '--quiet', paths[:upstream], paths[:upstream_dump], paths[:fork_dump])
      merged if status.success?
    end
  end

  def ensure_loads_as!(schema_path, expected_dump, header)
    loaded_dump = with_scratch_database('chatwoot_schema_verify') do
      load_schema(schema_path)
      dump.sub(SCHEMA_HEADER, header)
    end
    return if loaded_dump == expected_dump

    raise Error, "o db/schema.rb gerado não reproduz o banco com as migrations do fork:\n#{dump_diff(expected_dump, loaded_dump)}"
  end

  def ensure_fork_versions_recorded!
    missing = fork_versions - pool.schema_migration.integer_versions
    return if missing.empty?

    raise Error, "a versão do db/schema.rb é anterior às migrations do fork #{missing.join(', ')}: " \
                 'num banco novo elas rodariam por cima das tabelas que o schema já cria. Regenere o db/schema.rb.'
  end

  def revert!(version)
    pool.migration_context.run(:down, version)
  rescue StandardError => e
    raise Error, "não foi possível desfazer a migration do fork #{version}: a tabela ou coluna dela " \
                 "não está no db/schema.rb como a migration cria.\n#{e.message}"
  end

  def ensure_same_dump!(loaded, migrated)
    return if loaded == migrated

    raise Error, "o db/schema.rb não bate com o que as migrations do fork geram:\n#{dump_diff(loaded, migrated)}"
  end

  def dump_diff(expected, actual)
    Dir.mktmpdir do |dir|
      expected_path = File.join(dir, 'esperado.rb')
      actual_path = File.join(dir, 'obtido.rb')
      File.write(expected_path, expected)
      File.write(actual_path, actual)
      Open3.capture2('diff', '-u', expected_path, actual_path).first
    end
  end
end
