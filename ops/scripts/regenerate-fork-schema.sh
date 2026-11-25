#!/usr/bin/env bash
# Regenera o db/schema.rb = schema.rb do upstream (na ref indicada) + migrations do fork
# (ops/upstream-sync/fork-migrations.txt), confere o resultado com check-fork-schema.sh
# e faz "git add db/schema.rb".
#
# Chamado pelo ops/scripts/sync-upstream.sh. Rode à mão quando o sync pedir (ex.: após
# resolver outros conflitos, ou se ele foi rodado com --skip-schema):
#   ops/scripts/regenerate-fork-schema.sh v4.21.0
#
# Usa bancos descartáveis (<prefixo>_sync_<pid>_<aleatório>) apagados ao final; o banco do
# ambiente não é alterado (o boot do Rails pode, no máximo, lê-lo). Requer Ruby/gems do projeto (roda "bundle install" se faltar gem) e um
# Postgres com pgvector acessível pela configuração de banco do ambiente.
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "Uso: $0 <ref-do-upstream>   (ex.: $0 v4.21.0)" >&2
  exit 1
fi
upstream_ref="$1"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

upstream_schema="$(mktemp)"
trap 'rm -f "$upstream_schema"' EXIT
if ! git show "${upstream_ref}:db/schema.rb" > "$upstream_schema"; then
  echo "Erro: não encontrei db/schema.rb em ${upstream_ref}." >&2
  exit 1
fi

if ! bundle check >/dev/null 2>&1; then
  echo "==> Instalando as gems do Gemfile.lock atual (bundle install)"
  bundle install
fi

echo "==> Regenerando db/schema.rb: schema do upstream ${upstream_ref} + migrations do fork"
bundle exec rails fork:schema:regenerate UPSTREAM_SCHEMA="$upstream_schema"

"$script_dir/check-fork-schema.sh"

git add db/schema.rb
echo "==> db/schema.rb regenerado, conferido e adicionado ao índice (git add)."
