#!/usr/bin/env bash
# Atualiza o fork para uma nova release do Chatwoot (upstream).
#
# Uso (a partir de uma main limpa e atualizada):
#   ops/scripts/sync-upstream.sh v4.21.0
#
# O que faz:
#   1. Busca a tag no upstream (github.com/chatwoot/chatwoot), com histórico.
#   2. Cria a branch sync/upstream-<tag> a partir do HEAD atual.
#   3. Faz o merge da tag.
#   4. Resolve sozinho os conflitos previstos:
#        - caminhos em ops/upstream-sync/removed-paths.txt -> mantém removidos
#        - caminhos em ops/upstream-sync/ours-paths.txt    -> mantém a versão do fork
#   5. Atualiza ops/UPSTREAM_VERSION e, sem conflitos restantes, cria o commit.
#   6. Imprime o checklist de revisão (migrations, .env.example, workflows novos...).
#
# Nada é enviado ao GitHub: revise, rode os testes e abra um PR da branch gerada.
set -euo pipefail

UPSTREAM_URL="https://github.com/chatwoot/chatwoot.git"
TAG="${1:-}"

if [[ -z "$TAG" ]]; then
  echo "Uso: $0 <tag-do-upstream>   (ex.: $0 v4.21.0)" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

removed_list="ops/upstream-sync/removed-paths.txt"
ours_list="ops/upstream-sync/ours-paths.txt"
version_file="ops/UPSTREAM_VERSION"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Erro: há alterações não commitadas. Faça commit ou stash antes." >&2
  exit 1
fi

current_version="$(tr -d '[:space:]' < "$version_file")"
if [[ "$current_version" == "$TAG" ]]; then
  echo "O fork já está em $TAG. Nada a fazer."
  exit 0
fi

if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "Adicionando remote 'upstream' -> $UPSTREAM_URL"
  git remote add upstream "$UPSTREAM_URL"
fi

echo "==> Buscando $TAG no upstream..."
git fetch --no-tags upstream "refs/tags/${TAG}:refs/tags/${TAG}"
git fetch --no-tags upstream "refs/tags/${current_version}:refs/tags/${current_version}" 2>/dev/null || true

sync_branch="sync/upstream-${TAG}"
echo "==> Criando branch $sync_branch"
git checkout -b "$sync_branch"

# Lê uma lista ignorando comentários e linhas vazias.
read_list() {
  grep -v '^[[:space:]]*#' "$1" | sed '/^[[:space:]]*$/d'
}

# Diz se um caminho bate com algum item da lista (exato, ou prefixo se o item termina em "/").
matches_list() {
  local path="$1" list_file="$2" entry
  while IFS= read -r entry; do
    if [[ "$entry" == */ ]]; then
      [[ "$path" == "$entry"* ]] && return 0
    else
      [[ "$path" == "$entry" ]] && return 0
    fi
  done < <(read_list "$list_file")
  return 1
}

echo "==> Fazendo merge de $TAG..."
git merge --no-ff --no-commit "$TAG" || true

# 1) Conflitos previstos.
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if matches_list "$path" "$removed_list"; then
    git rm -q -r --cached --ignore-unmatch -- "$path"
    rm -rf -- "$path"
    echo "   resolvido (mantido removido): $path"
  elif matches_list "$path" "$ours_list"; then
    git checkout --ours -- "$path"
    git add -- "$path"
    echo "   resolvido (versão do fork):   $path  <- REVISE o que mudou no upstream"
  fi
done < <(git diff --name-only --diff-filter=U)

# 2) Arquivos novos do upstream dentro de caminhos que removemos (ex.: diretórios).
while IFS= read -r entry; do
  if [[ -n "$(git ls-files -- "$entry")" ]]; then
    git rm -q -r -f --cached -- "$entry"
    rm -rf -- "$entry"
    echo "   removido de novo (veio do upstream): $entry"
  fi
done < <(read_list "$removed_list")

echo "$TAG" > "$version_file"
git add "$version_file"

remaining="$(git diff --name-only --diff-filter=U)"
if [[ -n "$remaining" ]]; then
  echo
  echo "!! Conflitos que precisam de resolução manual:"
  printf '   %s\n' $remaining
  echo
  echo "Resolva, rode 'git add <arquivos>' e finalize com:"
  echo "   git commit -m \"chore(upstream): merge chatwoot ${TAG}\""
  exit 2
fi

git commit -q -m "chore(upstream): merge chatwoot ${TAG}"
echo "==> Merge de $TAG concluído na branch $sync_branch"

echo
echo "================ CHECKLIST DE REVISÃO ================"
echo "Release notes: https://github.com/chatwoot/chatwoot/releases/tag/${TAG}"
echo
echo "-- Migrations novas (rodam no deploy via db:chatwoot_prepare):"
git diff --name-only "$current_version" "$TAG" -- db/migrate | sed 's/^/   /' || true
echo
echo "-- Mudanças no .env.example (compare com ops/env/production.env.example):"
git diff --stat "$current_version" "$TAG" -- .env.example | sed 's/^/   /' || true
echo
echo "-- Workflows do GitHub Actions novos ou alterados (avalie se devem ser removidos aqui):"
git diff --name-status "$current_version" "$TAG" -- .github/workflows | sed 's/^/   /' || true
echo
echo "-- Versões de runtime (Ruby/Node) e Dockerfile:"
git diff --stat "$current_version" "$TAG" -- .ruby-version .nvmrc docker/Dockerfile | sed 's/^/   /' || true
echo
echo "Próximos passos: push da branch, PR para main, CI verde, build da imagem CE."
