#!/usr/bin/env bash
# Lê nomes de tags da entrada padrão e imprime as que a retenção do espelho deve apagar.
# Usado por .github/workflows/fork-upstream-mirror.yml.
#
# Uso: select-mirror-releases-to-delete.sh <prefixo> <quantas-manter> <tag-protegida> < tags.txt
#
# - Só considera tags no formato <prefixo>AAAA-MM-DD ou <prefixo>AAAA-MM-DD-N; qualquer outra é ignorada
#   (nunca será apagada).
# - Ordena da mais nova para a mais antiga: data (texto) e depois sufixo numérico
#   (sem sufixo = 1, então 2026-12-01-10 > 2026-12-01-9 > 2026-12-01).
# - Mantém as <quantas-manter> mais novas; a tag protegida (a criada na execução atual) nunca é listada.
set -euo pipefail

prefix="${1:?prefixo}"
keep="${2:?quantas manter}"
protected_tag="${3:?tag protegida}"

while IFS= read -r tag; do
  [[ "$tag" == "$prefix"* ]] || continue
  rest="${tag#"$prefix"}"
  if [[ "$rest" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})(-([0-9]+))?$ ]]; then
    printf '%s %d %s\n' "${BASH_REMATCH[1]}" "$((10#${BASH_REMATCH[3]:-1}))" "$tag"
  fi
done | sort -k1,1r -k2,2nr | tail -n +"$((keep + 1))" | while read -r _ _ tag; do
  [[ "$tag" == "$protected_tag" ]] || echo "$tag"
done
