# Mantém o db/schema.rb com as tabelas do fork (ver lib/fork/schema_sync.rb e
# docs/fork/atualizar-upstream.md). Os scripts ops/scripts/regenerate-fork-schema.sh
# e ops/scripts/check-fork-schema.sh são a forma normal de chamar estes tasks.
namespace :fork do
  namespace :schema do
    desc 'Regenera o db/schema.rb a partir do schema do upstream (UPSTREAM_SCHEMA=<arquivo>) + migrations do fork, ' \
         'num banco descartável'
    task regenerate: 'db:load_config' do
      result = Fork::SchemaSync.new.regenerate!(upstream_schema: ENV.fetch('UPSTREAM_SCHEMA'), output: Rails.root.join('db/schema.rb'))
      puts 'db/schema.rb regenerado: schema do upstream + migrations do fork.'
      if result == :full_dump
        puts 'ATENÇÃO: as tabelas do fork não puderam ser encaixadas no texto do upstream sem conflito; foi gravado o dump ' \
             'completo (correto, mas o diff contra o upstream traz também diferenças de formatação do dumper local).'
      end
    rescue Fork::SchemaSync::Error => e
      abort "Erro ao regenerar o db/schema.rb: #{e.message}"
    end

    desc 'Confere, num banco descartável, se o db/schema.rb reflete as migrations do fork (ops/upstream-sync/fork-migrations.txt)'
    task check: 'db:load_config' do
      Fork::SchemaSync.new.check!(schema: Rails.root.join('db/schema.rb'))
      puts 'db/schema.rb OK: reflete todas as migrations do fork.'
    rescue Fork::SchemaSync::Error => e
      abort "db/schema.rb inconsistente com as migrations do fork: #{e.message}"
    end
  end
end
