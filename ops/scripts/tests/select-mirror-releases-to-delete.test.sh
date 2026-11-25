#!/usr/bin/env bash
# Teste offline da seleção de Releases do espelho a apagar.
# Uso: bash ops/scripts/tests/select-mirror-releases-to-delete.test.sh
set -uo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/select-mirror-releases-to-delete.sh"
failures=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "OK     $name"
  else
    echo "FALHOU $name (esperado: [$expected] obtido: [$actual])"
    failures=$((failures + 1))
  fi
}

p="upstream-mirror-"

# Ordem por data e por sufixo numérico; mantém 3, apaga o resto.
actual="$(printf '%s\n' ${p}2026-12-01 ${p}2026-12-01-9 ${p}2026-12-01-10 ${p}2026-11-30 ${p}2026-11-01 ${p}2026-12-01-2 \
  | bash "$script" "$p" 3 "${p}2026-12-01-10" | tr '\n' ' ')"
check "ordena data e sufixo numérico" "${p}2026-12-01 ${p}2026-11-30 ${p}2026-11-01 " "$actual"

# Menos tags que o limite: nada a apagar.
actual="$(printf '%s\n' ${p}2026-12-01 ${p}2026-11-01 | bash "$script" "$p" 8 "${p}2026-12-01" | tr '\n' ' ')"
check "abaixo do limite não apaga nada" "" "$actual"

# Tags de outras Releases ou fora do formato nunca entram.
actual="$(printf '%s\n' release-1 v4.20.1 ${p}manual ${p}2026-01-01 ${p}2026-02-01 other-${p}2026-01-01 \
  | bash "$script" "$p" 1 "${p}2026-02-01" | tr '\n' ' ')"
check "ignora tags fora do prefixo e do formato" "${p}2026-01-01 " "$actual"

# A tag protegida nunca é apagada, mesmo se ficar fora do limite.
actual="$(printf '%s\n' ${p}2026-03-01 ${p}2026-02-01 ${p}2026-01-01 | bash "$script" "$p" 1 "${p}2026-01-01" | tr '\n' ' ')"
check "nunca apaga a tag da execução atual" "${p}2026-02-01 " "$actual"

# Limite de 8 com 10 tags.
actual="$(for m in 01 02 03 04 05 06 07 08 09 10; do echo "${p}2026-$m-01"; done | bash "$script" "$p" 8 "${p}2026-10-01" | tr '\n' ' ')"
check "mantém as 8 mais novas" "${p}2026-02-01 ${p}2026-01-01 " "$actual"

[[ $failures -eq 0 ]] || { echo "$failures caso(s) falharam."; exit 1; }
echo "Todos os casos passaram."
