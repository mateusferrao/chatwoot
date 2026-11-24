#!/usr/bin/env bash
# Gera os segredos necessários para uma instalação nova do Chatwoot e os
# imprime no formato .env. NÃO grava nada em disco: copie a saída direto para
# as variáveis de ambiente do Easypanel (ou do seu gerenciador de segredos).
#
# Gere um conjunto diferente para cada ambiente (produção, staging...).
# As chaves ACTIVE_RECORD_ENCRYPTION_* NUNCA podem mudar depois que o banco
# estiver em uso: elas criptografam dados (ex.: MFA). Guarde-as com cuidado.
set -euo pipefail

if ! command -v openssl >/dev/null 2>&1; then
  echo "Erro: openssl não encontrado." >&2
  exit 1
fi

alnum() {
  # Gera uma string alfanumérica com o tamanho pedido.
  local length="$1" value=""
  while [[ ${#value} -lt $length ]]; do
    value+="$(openssl rand -base64 64 | tr -dc 'A-Za-z0-9')"
  done
  printf '%s' "${value:0:$length}"
}

cat <<OUT
# ---- Segredos gerados em $(date -u +%Y-%m-%dT%H:%M:%SZ) ----
SECRET_KEY_BASE=$(openssl rand -hex 64)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(alnum 32)
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(alnum 32)
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(alnum 32)
POSTGRES_PASSWORD=$(openssl rand -hex 24)
REDIS_PASSWORD=$(openssl rand -hex 24)
OUT
