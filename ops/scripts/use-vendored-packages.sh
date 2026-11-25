#!/usr/bin/env bash
# Modo de emergência: troca as dependências publicadas pela Chatwoot Inc. pelas
# cópias guardadas em vendor/fork-mirror/, para gerar a imagem mesmo se o npm e o
# RubyGems tiverem despublicado esses pacotes. NÃO é usado no build normal.
#
# Uso:
#   ops/scripts/use-vendored-packages.sh                          # aplica (package.json, Gemfile e lockfiles)
#   ops/scripts/use-vendored-packages.sh --dockerfile <saida>     # aplica e gera um Dockerfile derivado
#   ops/scripts/use-vendored-packages.sh --dockerfile-only <saida>  # só gera o Dockerfile derivado
#   ops/scripts/use-vendored-packages.sh --check                  # só confere a cópia, sem alterar nada
#
# Procedimento completo: docs/fork/independencia-upstream.md
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/vendored-packages.sh
source "$repo_root/ops/scripts/lib/vendored-packages.sh"
cd "$repo_root"

mode=apply
dockerfile_out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) mode=check; shift ;;
    --dockerfile) dockerfile_out="${2:?Informe o arquivo de saída após --dockerfile}"; shift 2 ;;
    --dockerfile-only) mode=dockerfile; dockerfile_out="${2:?Informe o arquivo de saída após --dockerfile-only}"; shift 2 ;;
    *) echo "Opção desconhecida: $1" >&2; exit 2 ;;
  esac
done

errors=0
problem() { echo "ERRO: $*" >&2; errors=$((errors + 1)); }

# Confere se a cópia está completa e íntegra. Preenche npm_packages e gem_packages.
npm_packages=()   # "<nome> <versão>"
gem_packages=()   # "<gem> <versão>"
verify_mirror() {
  local mirror manifest kind package version origin hash date name tarball gemspec
  mirror="$(mirror_dir)"
  manifest="$mirror/MANIFEST.txt"
  if [[ ! -f "$manifest" ]]; then
    problem "falta $manifest (rode ops/scripts/refresh-vendored-packages.sh)"
    return
  fi

  while read -r kind package version origin hash date; do
    case "$kind" in
      npm)
        name="${package#@chatwoot/}"
        tarball="$mirror/npm/$(npm_tarball_name "$name" "$version")"
        if [[ ! -f "$tarball" ]]; then
          problem "falta $tarball"
        elif [[ "$(npm_integrity_of "$tarball")" != "$hash" ]]; then
          problem "$tarball não bate com o hash do MANIFEST.txt"
        fi
        npm_packages+=("$name $version")
        ;;
      gem)
        gemspec="$mirror/gems/$(gem_dir_name "$package" "$version")/$package.gemspec"
        if [[ ! -f "$gemspec" ]]; then
          problem "falta $gemspec"
        fi
        gem_packages+=("$package $version")
        ;;
      *) problem "tipo desconhecido no MANIFEST.txt: $kind" ;;
    esac
  done < <(manifest_entries)

  # Todo pacote do escopo precisa estar na cópia, na versão que o lockfile usa hoje.
  local lock_name lock_version lock_integrity lock_tarball gem_name lock_gem_version found
  while read -r lock_name lock_version lock_integrity; do
    found=0
    for entry in "${npm_packages[@]}"; do
      if [[ "$entry" == "$lock_name $lock_version" ]]; then found=1; fi
    done
    if [[ "$found" -eq 0 ]]; then
      problem "@chatwoot/$lock_name@$lock_version (pnpm-lock.yaml) não está em vendor/fork-mirror/; rode refresh-vendored-packages.sh"
    else
      # Com o lockfile ainda no registro, o tarball precisa bater com o integrity DELE (não só com o MANIFEST).
      lock_tarball="$mirror/npm/$(npm_tarball_name "$lock_name" "$lock_version")"
      if [[ -f "$lock_tarball" && "$(npm_integrity_of "$lock_tarball")" != "$lock_integrity" ]]; then
        problem "$lock_tarball não bate com o integrity do pnpm-lock.yaml"
      fi
    fi
  done < <(lockfile_npm_packages)
  for gem_name in "${VENDORED_GEMS[@]}"; do
    lock_gem_version="$(lockfile_gem_version "$gem_name")"
    found=0
    for entry in "${gem_packages[@]}"; do
      if [[ "$entry" == "$gem_name $lock_gem_version" ]]; then found=1; fi
    done
    # Com o modo de emergência já aplicado a gem sai do bloco GEM do lock; aí não há o que comparar.
    if [[ -n "$lock_gem_version" && "$found" -eq 0 ]]; then
      problem "$gem_name $lock_gem_version (Gemfile.lock) não está em vendor/fork-mirror/; rode refresh-vendored-packages.sh"
    fi
  done
  if [[ "${#gem_packages[@]}" -ne "${#VENDORED_GEMS[@]}" ]]; then
    problem "o MANIFEST.txt deveria ter ${#VENDORED_GEMS[@]} gems (${VENDORED_GEMS[*]}) e tem ${#gem_packages[@]}"
  fi
  if [[ "${#npm_packages[@]}" -eq 0 ]]; then
    problem "o MANIFEST.txt não tem pacotes npm"
  fi
}

# package.json: um override "@chatwoot/<nome>": "file:..." por pacote, mantendo os existentes.
apply_npm_overrides() {
  local entries=() entry name version
  for entry in "${npm_packages[@]}"; do
    name="${entry% *}"; version="${entry#* }"
    entries+=("@chatwoot/$name=file:vendor/fork-mirror/npm/$(npm_tarball_name "$name" "$version")")
  done
  python3 - package.json "${entries[@]}" <<'PY'
import json, sys
path, pairs = sys.argv[1], sys.argv[2:]
with open(path, encoding="utf-8") as handle:
    package = json.load(handle)
overrides = package.setdefault("pnpm", {}).setdefault("overrides", {})
for pair in pairs:
    key, value = pair.split("=", 1)
    overrides[key] = value
with open(path, "w", encoding="utf-8") as handle:
    json.dump(package, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
  pnpm install --lockfile-only
}

# Gemfile: as linhas das gems viram `gem '<nome>', path: '...'` (comentários não mudam).
apply_gem_paths() {
  local entry gem_name version
  for entry in "${gem_packages[@]}"; do
    gem_name="${entry% *}"; version="${entry#* }"
    sed -i.bak -E "s|^gem '${gem_name}'.*$|gem '${gem_name}', path: 'vendor/fork-mirror/gems/$(gem_dir_name "$gem_name" "$version")'|" Gemfile
  done
  rm -f Gemfile.bak
  for entry in "${gem_packages[@]}"; do
    gem_name="${entry% *}"; version="${entry#* }"
    if ! grep -qxF "gem '${gem_name}', path: 'vendor/fork-mirror/gems/$(gem_dir_name "$gem_name" "$version")'" Gemfile; then
      echo "ERRO: não consegui reescrever a linha da gem ${gem_name} no Gemfile (esperava aspas simples: gem '${gem_name}', ...). Edite à mão e rode bundle lock --local." >&2
      exit 1
    fi
  done
  bundle lock --local
}

# Dockerfile derivado: copia vendor/fork-mirror antes do bundle install e do pnpm i,
# que é onde o Gemfile (path:) e o package.json (file:) precisam encontrar as cópias.
write_derived_dockerfile() {
  local source="$repo_root/docker/Dockerfile" anchor='COPY Gemfile Gemfile.lock ./'
  if [[ "$(grep -cx -- "$anchor" "$source")" -ne 1 ]]; then
    echo "ERRO: não achei a linha '$anchor' (uma única vez) em docker/Dockerfile; ajuste ops/scripts/use-vendored-packages.sh." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dockerfile_out")"
  awk -v anchor="$anchor" '
    $0 == anchor { print "COPY vendor/fork-mirror ./vendor/fork-mirror" }
    { print }
  ' "$source" > "$dockerfile_out"
  echo "Dockerfile derivado: $dockerfile_out (docker/Dockerfile não foi alterado)"
}

if [[ "$mode" == "dockerfile" ]]; then
  write_derived_dockerfile
  exit 0
fi

verify_mirror
if [[ "$errors" -gt 0 ]]; then
  echo "Cópia em vendor/fork-mirror/ incompleta ou inconsistente ($errors problema(s))." >&2
  exit 1
fi

if [[ "$mode" == "check" ]]; then
  echo "OK: vendor/fork-mirror/ completa (${#npm_packages[@]} pacotes npm, ${#gem_packages[@]} gems), hashes conferem com o MANIFEST.txt."
  exit 0
fi

echo "Aplicando o modo de emergência (pacotes da Chatwoot Inc. vindos de vendor/fork-mirror/)..."
apply_gem_paths
apply_npm_overrides
if [[ -n "$dockerfile_out" ]]; then
  write_derived_dockerfile
fi

echo
echo "Resumo das alterações:"
git -C "$repo_root" diff --stat -- package.json pnpm-lock.yaml Gemfile Gemfile.lock 2>/dev/null || true
cat <<'NEXT'

Próximos passos:
  1. Revise o diff (git diff package.json Gemfile Gemfile.lock) e rode `pnpm install --frozen-lockfile` e `bundle check`.
  2. Crie uma branch de emergência (ex.: emergencia/pacotes-locais), faça commit e abra um PR.
  3. Gere a imagem com o workflow "Fork - imagem CE" nessa branch (para o Dockerfile derivado, use --dockerfile).
  Para voltar ao normal, descarte a branch de emergência: a main não foi alterada.
NEXT
