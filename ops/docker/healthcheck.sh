#!/bin/sh
# Healthcheck da imagem CE do fork (HEALTHCHECK adicionado no build por
# .github/workflows/fork-ce-image.yml). A mesma imagem roda dois processos:
#
# - Rails (Puma): saudável quando GET /api responde 2xx. O header
#   X-Forwarded-Proto evita o redirect 301 do FORCE_SSL=true (127.0.0.1 é
#   proxy confiável para o Rails).
# - Sidekiq: saudável quando o sidekiq_alive (gem já presente no Gemfile)
#   responde na porta SIDEKIQ_ALIVE_PORT (padrão 7433).
#
# Usa o wget do BusyBox (curl não existe na imagem de produção).
wget -q -T 5 --header "X-Forwarded-Proto: https" -O /dev/null "http://127.0.0.1:3000/api" && exit 0
wget -q -T 5 -O /dev/null "http://127.0.0.1:${SIDEKIQ_ALIVE_PORT:-7433}/" && exit 0
exit 1
