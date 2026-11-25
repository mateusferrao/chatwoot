#!/usr/bin/env bash
# Teste de ponta a ponta da etapa de schema do ops/scripts/sync-upstream.sh e do
# ops/scripts/check-fork-schema.sh, contra o repo real numa cópia descartável.
#
# Monta um "upstream" sintético a partir da tag em ops/UPSTREAM_VERSION que adiciona uma
# coluna em "accounts" (com a migration) e muda a versão do db/schema.rb, o que conflita
# com o schema do fork. Roda o sync com --source <bundle> e confere que o db/schema.rb
# resultante é exatamente o do fork com a mudança do upstream, e que a checagem passa.
# Depois estraga o schema de três jeitos e confere que a checagem falha.
#
# É PESADO (clona o repo e sobe o Rails várias vezes; alguns minutos): não roda em CI.
# Requer Ruby/gems do projeto (rbenv) e Postgres com pgvector. Os bancos usados são
# descartáveis (<prefixo>_sync_<pid>); o banco do ambiente não é tocado. Ex.:
#   eval "$(rbenv init -)"
#   POSTGRES_PASSWORD=postgres POSTGRES_DATABASE=chatwoot_test_b REDIS_URL=redis://127.0.0.1:6379/5 \
#     bash ops/scripts/tests/sync-upstream-schema.test.sh
#
# Testa o estado ATUAL do working tree: os scripts, listas e o código Ruby da etapa de
# schema são copiados por cima do clone do HEAD antes de rodar.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Isola do git/hooks do usuário (HOME fica: rbenv e bundler dependem dele).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=teste GIT_AUTHOR_EMAIL=teste@example.com
export GIT_COMMITTER_NAME=teste GIT_COMMITTER_EMAIL=teste@example.com

failures=0
pass() { echo "OK     $1"; }
fail() { echo "FALHOU $1 ($2)"; failures=$((failures + 1)); }

tested_paths=(
  ops/scripts/sync-upstream.sh
  ops/scripts/regenerate-fork-schema.sh
  ops/scripts/check-fork-schema.sh
  ops/upstream-sync
  lib/fork/schema_sync.rb
  lib/tasks/fork_schema.rake
)

# --- fork: clone do HEAD + working tree atual da etapa de schema -----------------
fork="$work/fork"
git clone -q --shared "$repo" "$fork"
git -C "$fork" checkout -q -B fork-teste "$(git -C "$repo" rev-parse HEAD)"
git -C "$fork" remote remove origin
for path in "${tested_paths[@]}"; do
  rm -rf "${fork:?}/$path"
  cp -R "$repo/$path" "$fork/$path"
done
git -C "$fork" add -A
git -C "$fork" commit -q -m "fork: estado atual do working tree" || true

base_tag="$(tr -d '[:space:]' < "$fork/ops/UPSTREAM_VERSION")"
new_tag="${base_tag}-teste-schema"
new_version="2026_12_01_123456"
fork_schema_before="$work/fork-schema-antes.rb"
cp "$fork/db/schema.rb" "$fork_schema_before"

# Insere a coluna nova logo após a abertura da tabela accounts e troca a versão do schema.
upstream_change() {
  sed -e '/^  create_table "accounts"/a\    t.string "sync_test_marker"' \
      -e "s/define(version: [0-9_]*)/define(version: ${new_version})/" "$1"
}

# --- upstream sintético: base_tag + coluna em accounts, vira bundle ---------------
(
  cd "$fork"
  export GIT_INDEX_FILE="$work/upstream.index"
  git read-tree "$base_tag"
  git show "${base_tag}:db/schema.rb" > "$work/upstream-base-schema.rb"
  upstream_change "$work/upstream-base-schema.rb" > "$work/upstream-schema.rb"
  cat > "$work/migration.rb" <<'RUBY'
class AddSyncTestMarkerToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :sync_test_marker, :string
  end
end
RUBY
  git update-index --add --cacheinfo "100644,$(git hash-object -w "$work/upstream-schema.rb"),db/schema.rb"
  git update-index --add --cacheinfo \
    "100644,$(git hash-object -w "$work/migration.rb"),db/migrate/${new_version//_/}_add_sync_test_marker_to_accounts.rb"
  commit="$(git commit-tree "$(git write-tree)" -p "${base_tag}^{commit}" -m "upstream sintético")"
  git tag "$new_tag" "$commit"
  git bundle create -q "$work/upstream.bundle" "$new_tag" "^${base_tag}"
  git tag -d "$new_tag" >/dev/null
)

expected="$work/schema-esperado.rb"
upstream_change "$fork_schema_before" > "$expected"

# 1) --skip-schema: para com o db/schema.rb em conflito e avisa (sem Rails).
skip="$work/fork-skip"
git clone -q --shared "$fork" "$skip"
git -C "$skip" remote remove origin
out="$(cd "$skip" && bash ops/scripts/sync-upstream.sh --source "$work/upstream.bundle" --skip-schema "$new_tag" 2>&1)"; code=$?
if [[ $code -eq 2 && "$out" == *"--skip-schema: o db/schema.rb NÃO foi regenerado"* \
      && "$(git -C "$skip" diff --name-only --diff-filter=U)" == "db/schema.rb" ]]; then
  pass "--skip-schema para com o db/schema.rb em conflito e avisa"
else
  fail "--skip-schema para com o db/schema.rb em conflito e avisa" "exit=$code: $out"
fi

# 2) sync completo: regenera o schema e commita.
out="$(cd "$fork" && bash ops/scripts/sync-upstream.sh --source "$work/upstream.bundle" "$new_tag" 2>&1)"; code=$?
echo "$out" > "$work/sync.log"
branch="$(git -C "$fork" rev-parse --abbrev-ref HEAD)"
if [[ $code -eq 0 && "$branch" == "sync/upstream-${new_tag}" && -z "$(git -C "$fork" status --porcelain)" \
      && "$(git -C "$fork" log -1 --format=%s)" == "chore(upstream): merge chatwoot ${new_tag}" ]]; then
  pass "sync com conflito no db/schema.rb termina com commit"
else
  fail "sync com conflito no db/schema.rb termina com commit" "exit=$code branch=$branch: $(tail -40 "$work/sync.log")"
fi

if [[ "$out" == *"db/schema.rb REGENERADO"* && "$out" == *"git diff ${new_tag} -- db/schema.rb"* ]]; then
  pass "checklist avisa que o db/schema.rb foi regenerado e pede revisão do diff"
else
  fail "checklist avisa que o db/schema.rb foi regenerado e pede revisão do diff" "$(tail -20 "$work/sync.log")"
fi

# 3) resultado = schema do fork + coluna do upstream + versão nova, byte a byte.
if diff -u "$expected" "$fork/db/schema.rb" > "$work/schema.diff"; then
  pass "db/schema.rb = schema do fork + mudança do upstream (byte a byte)"
else
  fail "db/schema.rb = schema do fork + mudança do upstream (byte a byte)" "$(head -40 "$work/schema.diff")"
fi

fork_tables="$(grep -c '^  create_table "automato_agents_' "$fork/db/schema.rb")"
if [[ "$fork_tables" -eq "$(grep -c '^  create_table "automato_agents_' "$fork_schema_before")" && "$fork_tables" -gt 0 \
      && "$(grep -c 't.string "sync_test_marker"' "$fork/db/schema.rb")" -eq 1 \
      && "$(grep -c "define(version: ${new_version})" "$fork/db/schema.rb")" -eq 1 ]]; then
  pass "db/schema.rb tem as $fork_tables tabelas automato_agents_*, a coluna e a versão do upstream"
else
  fail "db/schema.rb tem as tabelas automato_agents_*, a coluna e a versão do upstream" "tabelas=$fork_tables"
fi

# 4) checagem passa no resultado.
out="$(cd "$fork" && bash ops/scripts/check-fork-schema.sh 2>&1)"; code=$?
if [[ $code -eq 0 && "$out" == *"db/schema.rb OK"* ]]; then
  pass "check-fork-schema.sh passa no schema regenerado"
else
  fail "check-fork-schema.sh passa no schema regenerado" "exit=$code: $out"
fi

# 4b) upstream cujo texto não encaixa as mudanças do fork sem conflito: sem o comentário
#     das extensões, a linha da versão (que muda: o upstream base é anterior às migrations
#     do fork) fica colada nas linhas de extensão que o dumper local escreve diferente.
#     O script grava o dump completo, avisa, e o resultado continua passando na checagem.
(
  cd "$fork"
  export GIT_INDEX_FILE="$work/divergente.index"
  git read-tree HEAD
  git show "${base_tag}:db/schema.rb" | sed '/# These extensions should be enabled/d' > "$work/schema-divergente.rb"
  git update-index --add --cacheinfo "100644,$(git hash-object -w "$work/schema-divergente.rb"),db/schema.rb"
  git tag upstream-texto-divergente "$(git commit-tree "$(git write-tree)" -p HEAD -m "upstream com texto divergente")"
)
out="$(cd "$fork" && bash ops/scripts/regenerate-fork-schema.sh upstream-texto-divergente 2>&1)"; code=$?
if [[ $code -eq 0 && "$out" == *"ATENÇÃO"* && "$out" == *"db/schema.rb OK"* \
      && "$(grep -c '^  create_table "automato_agents_' "$fork/db/schema.rb")" -eq "$fork_tables" ]]; then
  pass "texto do upstream que conflita: grava o dump completo, avisa e passa na checagem"
else
  fail "texto do upstream que conflita: grava o dump completo, avisa e passa na checagem" "exit=$code: $(echo "$out" | tail -15)"
fi
git -C "$fork" reset -q --hard

# 5) checagem falha sem uma tabela do fork.
check_fails() {
  local name="$1" expected_message="$2" out code
  out="$(cd "$fork" && bash ops/scripts/check-fork-schema.sh 2>&1)"; code=$?
  if [[ $code -ne 0 && "$out" == *"$expected_message"* ]]; then
    pass "$name"
  else
    fail "$name" "exit=$code: $(echo "$out" | tail -15)"
  fi
  git -C "$fork" checkout -q -- .
  git -C "$fork" clean -q -fd -- db/migrate
}

sed -i '/^  create_table "automato_agents_steps"/,/^  end$/d; /add_foreign_key "automato_agents_steps"/d' "$fork/db/schema.rb"
check_fails "check-fork-schema.sh falha sem a tabela automato_agents_steps" "não foi possível desfazer a migration do fork 20261125190649"

# 6) checagem falha com coluna do fork diferente do que a migration cria.
sed -i 's/t.string "key_source", default: "automato", null: false/t.string "key_source", null: false/' "$fork/db/schema.rb"
check_fails "check-fork-schema.sh falha com coluna do fork diferente da migration" "não bate com o que as migrations do fork geram"

# 7) checagem falha com versão do schema anterior às migrations do fork.
sed -i 's/define(version: [0-9_]*)/define(version: 2026_11_16_211055)/' "$fork/db/schema.rb"
check_fails "check-fork-schema.sh falha com versão do schema anterior às migrations do fork" "é anterior às migrations do fork"

# 8) checagem falha com migration automato_agents fora do manifesto.
cp "$fork/db/migrate/20261125182006_create_automato_agents_account_settings.rb" \
   "$fork/db/migrate/20261202101010_create_automato_agents_extra.rb"
check_fails "check-fork-schema.sh falha com migration do fork fora do manifesto" \
  "fora de ops/upstream-sync/fork-migrations.txt (adicione-a lá): db/migrate/20261202101010_create_automato_agents_extra.rb"

# 9) nenhum banco descartável ficou para trás.
if command -v psql >/dev/null 2>&1; then
  leftovers="$(PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "${POSTGRES_HOST:-localhost}" -U "${POSTGRES_USERNAME:-postgres}" -d postgres -Atc \
    "select datname from pg_database where datname like 'chatwoot_schema_%_sync_%'")"
  if [[ -z "$leftovers" ]]; then
    pass "bancos descartáveis apagados"
  else
    fail "bancos descartáveis apagados" "$leftovers"
  fi
fi

echo
if [[ $failures -gt 0 ]]; then
  echo "$failures caso(s) falharam."
  exit 1
fi
echo "Todos os casos passaram."
