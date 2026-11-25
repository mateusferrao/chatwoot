#!/usr/bin/env bash
# Teste do ops/scripts/sync-upstream.sh (opção --source e uso padrão).
# Autocontido: roda em diretório temporário, sem rede e sem tocar no repositório real.
#
# Uso: bash ops/scripts/tests/sync-upstream-source.test.sh
set -uo pipefail

real_script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sync-upstream.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Isola do git/hooks do usuário.
export HOME="$work/home"
mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=teste GIT_AUTHOR_EMAIL=teste@example.com
export GIT_COMMITTER_NAME=teste GIT_COMMITTER_EMAIL=teste@example.com

failures=0
pass() { echo "OK     $1"; }
fail() { echo "FALHOU $1 ($2)"; failures=$((failures + 1)); }

# --- upstream sintético: v1.0.0 e v1.1.0 --------------------------------------
upstream="$work/upstream"
git init -q -b main "$upstream"
(
  cd "$upstream"
  echo "um"      > removed.txt
  echo "um"      > ours.txt
  echo "um"      > app.txt
  git add -A && git commit -q -m "v1.0.0" && git tag v1.0.0
) 

# --- fork sintético, clonado do upstream na v1.0.0 -----------------------------
fork_template="$work/fork-template"
git clone -q "$upstream" "$fork_template"
(
  cd "$fork_template"
  git remote remove origin
  mkdir -p ops/scripts ops/upstream-sync
  cp "$real_script" ops/scripts/sync-upstream.sh
  printf '# removidos\nremoved.txt\n' > ops/upstream-sync/removed-paths.txt
  printf '# nossos\nours.txt\n'       > ops/upstream-sync/ours-paths.txt
  printf '# deles\n'                 > ops/upstream-sync/theirs-paths.txt
  echo "v1.0.0" > ops/UPSTREAM_VERSION
  git rm -q removed.txt
  echo "fork" > ours.txt
  git add -A && git commit -q -m "fork"
)

# --- upstream avança para v1.1.0 e vira bundle ---------------------------------
(
  cd "$upstream"
  echo "dois" > removed.txt
  echo "dois" > ours.txt
  echo "dois" > app.txt
  git add -A && git commit -q -m "v1.1.0" && git tag v1.1.0
  git bundle create "$work/upstream.bundle" --all 2>/dev/null
)

new_fork() {
  local dest="$work/fork-$1"
  git clone -q "$fork_template" "$dest"
  echo "$dest"
}

# 1) --source <bundle> com sucesso
fork="$(new_fork bundle)"
out="$(cd "$fork" && bash ops/scripts/sync-upstream.sh --source "$work/upstream.bundle" v1.1.0 2>&1)"; code=$?
branch="$(git -C "$fork" rev-parse --abbrev-ref HEAD)"
version="$(tr -d '[:space:]' < "$fork/ops/UPSTREAM_VERSION")"
if [[ $code -eq 0 && "$branch" == "sync/upstream-v1.1.0" && "$version" == "v1.1.0" \
      && ! -e "$fork/removed.txt" && "$(cat "$fork/ours.txt")" == "fork" && "$(cat "$fork/app.txt")" == "dois" ]]; then
  pass "--source <bundle> atualiza para v1.1.0"
else
  fail "--source <bundle> atualiza para v1.1.0" "exit=$code branch=$branch versão=$version: $out"
fi

# 1b) não cria o remote upstream ao usar bundle
if git -C "$fork" remote get-url upstream >/dev/null 2>&1; then
  fail "--source <bundle> não cria remote upstream" "remote criado"
else
  pass "--source <bundle> não cria remote upstream"
fi

# 2) bundle inexistente
fork="$(new_fork missing)"
out="$(cd "$fork" && bash ops/scripts/sync-upstream.sh --source "$work/nao-existe.bundle" v1.1.0 2>&1)"; code=$?
if [[ $code -ne 0 && "$out" == *"não encontrado"* ]]; then
  pass "--source com arquivo inexistente falha com mensagem"
else
  fail "--source com arquivo inexistente falha com mensagem" "exit=$code: $out"
fi

# 3) tag que não existe no bundle
fork="$(new_fork notag)"
out="$(cd "$fork" && bash ops/scripts/sync-upstream.sh --source "$work/upstream.bundle" v9.9.9 2>&1)"; code=$?
if [[ $code -ne 0 ]]; then
  pass "tag inexistente no bundle falha"
else
  fail "tag inexistente no bundle falha" "exit=$code: $out"
fi

# 4) arquivo que não é bundle
echo "lixo" > "$work/invalido.bundle"
fork="$(new_fork invalid)"
out="$(cd "$fork" && bash ops/scripts/sync-upstream.sh --source "$work/invalido.bundle" v1.1.0 2>&1)"; code=$?
if [[ $code -ne 0 ]]; then
  pass "bundle inválido falha na verificação"
else
  fail "bundle inválido falha na verificação" "exit=$code: $out"
fi

# 5) uso padrão (só <tag>), com remote upstream apontando para o repo local
fork="$(new_fork default)"
git -C "$fork" remote add upstream "$upstream"
out="$(cd "$fork" && bash ops/scripts/sync-upstream.sh v1.1.0 2>&1)"; code=$?
version="$(tr -d '[:space:]' < "$fork/ops/UPSTREAM_VERSION")"
if [[ $code -eq 0 && "$version" == "v1.1.0" ]]; then
  pass "uso padrão (<tag> sozinha) segue funcionando"
else
  fail "uso padrão (<tag> sozinha) segue funcionando" "exit=$code versão=$version: $out"
fi

# 6) argumentos inválidos
fork="$(new_fork args)"
out="$(cd "$fork" && bash ops/scripts/sync-upstream.sh --source 2>&1)"; code=$?
if [[ $code -ne 0 && "$out" == *"Uso:"* ]]; then
  pass "--source sem valor mostra o uso"
else
  fail "--source sem valor mostra o uso" "exit=$code: $out"
fi

echo
if [[ $failures -gt 0 ]]; then
  echo "$failures caso(s) falharam."
  exit 1
fi
echo "Todos os casos passaram."
