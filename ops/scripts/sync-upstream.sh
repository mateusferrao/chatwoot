#!/usr/bin/env bash
# Atualiza o fork para uma nova release do Chatwoot (upstream).
#
# Uso (a partir de uma main limpa e atualizada):
#   ops/scripts/sync-upstream.sh [--source <url-ou-caminho-de-bundle>] [--skip-schema] <tag>
#   ops/scripts/sync-upstream.sh v4.21.0
#   ops/scripts/sync-upstream.sh --source chatwoot-upstream.bundle v4.21.0
#
# Sem --source, busca no upstream oficial. Com --source, busca de um arquivo .bundle
# (espelho guardado pelo workflow "Fork - espelho do upstream") ou de outra URL git;
# nesse caso o remote 'upstream' não é criado nem alterado.
# Ver docs/fork/independencia-upstream.md.
#
# O que faz:
#   1. Busca a tag no upstream (github.com/chatwoot/chatwoot) ou na fonte de --source, com histórico.
#   2. Cria a branch sync/upstream-<tag> a partir do HEAD atual.
#   3. Faz o merge da tag.
#   4. Resolve sozinho os conflitos previstos:
#        - caminhos em ops/upstream-sync/removed-paths.txt -> mantém removidos
#        - caminhos em ops/upstream-sync/ours-paths.txt    -> mantém a versão do fork
#        - caminhos em ops/upstream-sync/theirs-paths.txt  -> usa a versão do upstream
#   5. Se o upstream mexeu em db/schema.rb ou db/migrate (ou o db/schema.rb conflitou),
#      regenera o db/schema.rb = schema do upstream + migrations do fork
#      (ops/upstream-sync/fork-migrations.txt) num banco descartável e o confere com
#      ops/scripts/check-fork-schema.sh (ver ops/scripts/regenerate-fork-schema.sh).
#      Requer Ruby/gems do projeto e Postgres com pgvector. --skip-schema pula esta etapa
#      (ex.: sem Postgres); aí o db/schema.rb fica para resolver à mão.
#   6. Atualiza ops/UPSTREAM_VERSION e, sem conflitos restantes, cria o commit.
#   7. Imprime o checklist de revisão (schema, migrations, .env.example, workflows novos...).
#
# Saídas: 0 = merge commitado; 2 = conflitos para resolver à mão; 3 = falha ao regenerar o
# db/schema.rb (merge em andamento, sem commit).
# Nada é enviado ao GitHub: revise, rode os testes e abra um PR da branch gerada.
set -euo pipefail

UPSTREAM_URL="https://github.com/chatwoot/chatwoot.git"
SOURCE=""
TAG=""
SKIP_SCHEMA=false

usage() {
  echo "Uso: $0 [--source <url-ou-bundle>] [--skip-schema] <tag-do-upstream>   (ex.: $0 v4.21.0)" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 && -n "$2" ]] || usage
      SOURCE="$2"
      shift 2
      ;;
    --skip-schema)
      SKIP_SCHEMA=true
      shift
      ;;
    -*)
      usage
      ;;
    *)
      [[ -z "$TAG" ]] || usage
      TAG="$1"
      shift
      ;;
  esac
done

[[ -n "$TAG" ]] || usage

# Fonte aceita: URL git (com "://") ou arquivo bundle. Um arquivo vira caminho absoluto (o script muda de diretório).
source_is_bundle=false
if [[ -n "$SOURCE" && "$SOURCE" != *://* ]]; then
  if [[ ! -f "$SOURCE" ]]; then
    echo "Erro: --source deve ser o caminho de um arquivo bundle existente ou uma URL git (com ://); não encontrado: $SOURCE" >&2
    echo "      Diretórios locais e endereços no formato git@host:repo não são suportados." >&2
    exit 1
  fi
  SOURCE="$(cd "$(dirname "$SOURCE")" && pwd)/$(basename "$SOURCE")"
  source_is_bundle=true
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

removed_list="ops/upstream-sync/removed-paths.txt"
ours_list="ops/upstream-sync/ours-paths.txt"
theirs_list="ops/upstream-sync/theirs-paths.txt"
version_file="ops/UPSTREAM_VERSION"
schema_file="db/schema.rb"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Erro: há alterações não commitadas. Faça commit ou stash antes." >&2
  exit 1
fi

current_version="$(tr -d '[:space:]' < "$version_file")"
if [[ "$current_version" == "$TAG" ]]; then
  echo "O fork já está em $TAG. Nada a fazer."
  exit 0
fi

if [[ -n "$SOURCE" ]]; then
  fetch_from="$SOURCE"
  if [[ "$source_is_bundle" == true ]]; then
    echo "==> Verificando o bundle $SOURCE"
    git bundle verify "$SOURCE" >/dev/null
  fi
else
  if ! git remote get-url upstream >/dev/null 2>&1; then
    echo "Adicionando remote 'upstream' -> $UPSTREAM_URL"
    git remote add upstream "$UPSTREAM_URL"
  fi
  fetch_from="upstream"
fi

echo "==> Buscando $TAG em $fetch_from..."
git fetch --no-tags "$fetch_from" "refs/tags/${TAG}:refs/tags/${TAG}"
git fetch --no-tags "$fetch_from" "refs/tags/${current_version}:refs/tags/${current_version}" 2>/dev/null || true

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

# 1) Conflitos previstos. O db/schema.rb é tratado na etapa do schema, mais abaixo.
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  if [[ "$path" == "$schema_file" ]]; then
    continue
  elif matches_list "$path" "$removed_list"; then
    git rm -q -r --cached --ignore-unmatch -- "$path"
    rm -rf -- "$path"
    echo "   resolvido (mantido removido): $path"
  elif matches_list "$path" "$ours_list"; then
    git checkout --ours -- "$path"
    git add -- "$path"
    echo "   resolvido (versão do fork):   $path  <- REVISE o que mudou no upstream"
  elif matches_list "$path" "$theirs_list"; then
    git checkout --theirs -- "$path"
    git add -- "$path"
    echo "   resolvido (versão do upstream): $path  <- revalide (ex.: bundle-audit) e limpe theirs-paths.txt se não precisar mais"
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

# 3) db/schema.rb: precisa ser regenerado se conflitou ou se o upstream mexeu no schema
#    ou em migrations (se a comparação entre as versões falhar, regenera por garantia).
schema_conflict=false
if git diff --name-only --diff-filter=U | grep -qxF "$schema_file"; then
  schema_conflict=true
fi
schema_needed=false
if [[ "$schema_conflict" == true ]] || ! git diff --quiet "$current_version" "$TAG" -- "$schema_file" db/migrate 2>/dev/null; then
  schema_needed=true
fi
schema_regenerated=false

remaining="$(git diff --name-only --diff-filter=U | grep -vxF "$schema_file" || true)"
if [[ -n "$remaining" ]]; then
  echo
  echo "!! Conflitos que precisam de resolução manual:"
  printf '   %s\n' $remaining
  echo
  if [[ "$schema_needed" == true ]]; then
    echo "!! O db/schema.rb também precisa ser regenerado. Depois de resolver os conflitos acima, rode:"
    echo "   ops/scripts/regenerate-fork-schema.sh ${TAG}"
    echo
  fi
  echo "Resolva, rode 'git add <arquivos>' e finalize com:"
  echo "   git commit -m \"chore(upstream): merge chatwoot ${TAG}\""
  exit 2
fi

if [[ "$schema_needed" == true && "$SKIP_SCHEMA" == true ]]; then
  echo
  echo "!! --skip-schema: o db/schema.rb NÃO foi regenerado com as tabelas do fork. Resolva à mão antes do PR:"
  echo "   ops/scripts/regenerate-fork-schema.sh ${TAG}"
  if [[ "$schema_conflict" == true ]]; then
    echo
    echo "!! Conflitos que precisam de resolução manual:"
    echo "   $schema_file"
    echo
    echo "Depois finalize com:"
    echo "   git commit -m \"chore(upstream): merge chatwoot ${TAG}\""
    exit 2
  fi
elif [[ "$schema_needed" == true ]]; then
  echo "==> O upstream mexeu no schema: regenerando db/schema.rb com as tabelas do fork..."
  schema_result_file="$(mktemp)"
  trap 'rm -f "$schema_result_file"' EXIT
  if ! FORK_SCHEMA_RESULT_FILE="$schema_result_file" "ops/scripts/regenerate-fork-schema.sh" "$TAG"; then
    echo
    echo "!! Falha ao regenerar o db/schema.rb (veja o erro acima). O merge segue em andamento, sem commit."
    echo "   Corrija o ambiente (Postgres, Ruby, bundle install) e rode:"
    echo "   ops/scripts/regenerate-fork-schema.sh ${TAG}"
    echo "   git commit -m \"chore(upstream): merge chatwoot ${TAG}\""
    echo "   Sem Postgres? Resolva o db/schema.rb à mão (schema do upstream + tabelas do fork) e"
    echo "   confira depois com ops/scripts/check-fork-schema.sh."
    exit 3
  fi
  schema_regenerated=true
fi

git commit -q -m "chore(upstream): merge chatwoot ${TAG}"
echo "==> Merge de $TAG concluído na branch $sync_branch"

echo
echo "================ CHECKLIST DE REVISÃO ================"
echo "Release notes: https://github.com/chatwoot/chatwoot/releases/tag/${TAG}"
echo
if [[ "$schema_regenerated" == true ]]; then
  echo "-- db/schema.rb REGENERADO (schema do upstream ${TAG} + migrations do fork) e conferido."
  echo "   REVISE o diff contra o upstream; deve mostrar só a versão e as tabelas/chaves do fork:"
  echo "   git diff ${TAG} -- ${schema_file}"
  if [[ "$(cat "$schema_result_file")" == "full_dump" ]]; then
    echo "   !! ATENÇÃO: as tabelas do fork não encaixaram no texto do upstream sem conflito; foi gravado o"
    echo "      dump completo (correto, mas o diff traz também diferenças de formatação do dumper local)."
  fi
  echo
elif [[ "$schema_needed" == true ]]; then
  echo "-- !! db/schema.rb NÃO regenerado (--skip-schema). Antes do PR rode:"
  echo "   ops/scripts/regenerate-fork-schema.sh ${TAG}   (e faça commit do db/schema.rb)"
  echo
fi
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
