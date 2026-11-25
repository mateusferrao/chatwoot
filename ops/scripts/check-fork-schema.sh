#!/usr/bin/env bash
# Confere se o db/schema.rb reflete as migrations próprias do fork
# (ops/upstream-sync/fork-migrations.txt). Falha (saída != 0) se:
#   - alguma migration listada não existe, ou há db/migrate/*automato_agents* fora da lista;
#   - a versão do db/schema.rb é anterior a alguma migration do fork;
#   - alguma tabela/coluna do fork falta no db/schema.rb ou está diferente do que a
#     migration cria.
#
# Como confere: carrega o db/schema.rb num banco descartável (<prefixo>_sync_<pid>_<aleatório>),
# desfaz as migrations do fork (falha se a tabela/coluna não existe), refaz e compara o
# dump com o de antes. Detalhes em lib/fork/schema_sync.rb.
#
# Requer Ruby/gems do projeto e um Postgres com pgvector acessível pela configuração
# de banco do ambiente (POSTGRES_HOST, POSTGRES_USERNAME, POSTGRES_PASSWORD...).
# O banco do ambiente (POSTGRES_DATABASE) não é alterado (o boot do Rails pode, no máximo, lê-lo).
#
# Uso: ops/scripts/check-fork-schema.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

echo "==> Conferindo o db/schema.rb contra as migrations do fork (ops/upstream-sync/fork-migrations.txt)"
bundle exec rails fork:schema:check
