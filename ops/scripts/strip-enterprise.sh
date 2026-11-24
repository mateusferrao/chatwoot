#!/usr/bin/env bash
# Remove o código Enterprise (licença proprietária da Chatwoot Inc.) para gerar
# a edição Community (CE), 100% MIT. Mesmo procedimento que o upstream usa no
# build oficial "-ce" (publish_foss_docker.yml) e no CI (run_foss_spec.yml).
#
# IMPORTANTE: a pasta enterprise/ continua versionada no git de propósito
# (merges limpos com o upstream). Este script só deve rodar em cópias
# descartáveis: build de imagem Docker, CI ou worktree temporário.
#
# Uso:
#   ops/scripts/strip-enterprise.sh            # em CI (variável CI=true)
#   ops/scripts/strip-enterprise.sh --confirm  # localmente, em worktree descartável
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

if [[ ! -f VERSION_CW || ! -d app ]]; then
  echo "Erro: $repo_root não parece a raiz do Chatwoot." >&2
  exit 1
fi

if [[ "${CI:-}" != "true" && "${1:-}" != "--confirm" ]]; then
  echo "Recusado: este script apaga enterprise/ e spec/enterprise/." >&2
  echo "Rode apenas em cópia descartável (CI, build, worktree) com --confirm." >&2
  exit 1
fi

rm -rf enterprise spec/enterprise
echo "Edição CE preparada: enterprise/ e spec/enterprise/ removidos de $repo_root"
