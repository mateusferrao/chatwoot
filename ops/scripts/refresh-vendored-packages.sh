#!/usr/bin/env bash
# Baixa (ou atualiza) em vendor/fork-mirror/ as cópias dos pacotes que a Chatwoot Inc.
# publica no npm e no RubyGems e que o build da imagem usa. Se ela despublicar esses
# pacotes, o modo de emergência (use-vendored-packages.sh) usa estas cópias.
#
# As versões são lidas do pnpm-lock.yaml e do Gemfile.lock. Cada arquivo é conferido:
#   - npm: sha512 ("integrity") do pnpm-lock.yaml; se não bater, o script falha;
#   - gems: sha256 informado pela API do RubyGems.
# Idempotente: o que já está na cópia e confere não é baixado de novo.
#
# Uso: ops/scripts/refresh-vendored-packages.sh
# Requer: curl, openssl, python3 e Ruby (comando gem).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=lib/vendored-packages.sh
source "$repo_root/ops/scripts/lib/vendored-packages.sh"
cd "$repo_root"

mirror="$(mirror_dir)"
manifest="$mirror/MANIFEST.txt"
today="$(date -u +%Y-%m-%d)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$mirror/npm" "$mirror/gems"

download() { curl --fail --silent --show-error --location --retry 3 --output "$2" "$1"; }

# Data da última vez que uma linha idêntica (mesmo pacote, versão e hash) entrou no MANIFEST,
# para que rodar o script de novo sem mudanças não gere diff.
previous_date() { # tipo pacote versão hash
  [[ -f "$manifest" ]] || return 0
  awk -v kind="$1" -v package="$2" -v version="$3" -v hash="$4" \
    '$1 == kind && $2 == package && $3 == version && $5 == hash { print $6 }' "$manifest" | head -n 1
}

new_manifest="$work/MANIFEST.txt"
cat > "$new_manifest" <<'HEADER'
# Cópia dos pacotes publicados pela Chatwoot Inc. (todos MIT). Gerado por ops/scripts/refresh-vendored-packages.sh; não edite à mão.
# tipo pacote versão origem hash-conferido data
HEADER

expected_npm_files=()
while read -r name version integrity; do
  file_name="$(npm_tarball_name "$name" "$version")"
  target="$mirror/npm/$file_name"
  origin="https://registry.npmjs.org/@chatwoot/$name/-/$name-$version.tgz"
  expected_npm_files+=("$file_name")

  if [[ -f "$target" && "$(npm_integrity_of "$target")" == "$integrity" ]]; then
    echo "npm  @chatwoot/$name $version: já está na cópia e confere."
  else
    echo "npm  @chatwoot/$name $version: baixando..."
    download "$origin" "$work/$file_name"
    if [[ "$(npm_integrity_of "$work/$file_name")" != "$integrity" ]]; then
      echo "ERRO: @chatwoot/$name@$version não bate com o integrity do pnpm-lock.yaml; nada foi gravado." >&2
      exit 1
    fi
    mv "$work/$file_name" "$target"
  fi
  echo "npm @chatwoot/$name $version $origin $integrity $(previous_date npm "@chatwoot/$name" "$version" "$integrity" | grep . || echo "$today")" >> "$new_manifest"
done < <(lockfile_npm_packages)

if [[ "${#expected_npm_files[@]}" -eq 0 ]]; then
  echo "ERRO: não achei pacotes @chatwoot/* no pnpm-lock.yaml (o modo de emergência já está aplicado nesta cópia?)." >&2
  exit 1
fi

expected_gem_dirs=()
for gem_name in "${VENDORED_GEMS[@]}"; do
  version="$(lockfile_gem_version "$gem_name")"
  if [[ -z "$version" ]]; then
    echo "ERRO: $gem_name não está no Gemfile.lock." >&2
    exit 1
  fi
  dir_name="$(gem_dir_name "$gem_name" "$version")"
  target="$mirror/gems/$dir_name"
  origin="https://rubygems.org/downloads/$dir_name.gem"
  expected_gem_dirs+=("$dir_name")

  expected_sha="$(download "https://rubygems.org/api/v2/rubygems/$gem_name/versions/$version.json" "$work/$dir_name.json" \
    && python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha"])' "$work/$dir_name.json")"
  if [[ ! "$expected_sha" =~ ^[0-9a-f]{64}$ ]]; then
    echo "ERRO: a API do RubyGems não devolveu o sha256 de $gem_name $version." >&2
    exit 1
  fi
  hash="sha256:$expected_sha"

  if [[ -f "$target/$gem_name.gemspec" && "$(previous_date gem "$gem_name" "$version" "$hash")" != "" ]]; then
    echo "gem  $gem_name $version: já está na cópia e confere."
  else
    echo "gem  $gem_name $version: baixando..."
    download "$origin" "$work/$dir_name.gem"
    if [[ "$(openssl dgst -sha256 "$work/$dir_name.gem" | awk '{print $NF}')" != "$expected_sha" ]]; then
      echo "ERRO: $dir_name.gem não bate com o sha256 da API do RubyGems; nada foi gravado." >&2
      exit 1
    fi
    gem unpack "$work/$dir_name.gem" --target="$work/unpacked" > /dev/null
    gem spec --ruby "$work/$dir_name.gem" > "$work/unpacked/$dir_name/$gem_name.gemspec"
    rm -rf "$target"
    mv "$work/unpacked/$dir_name" "$target"
  fi
  echo "gem $gem_name $version $origin $hash $(previous_date gem "$gem_name" "$version" "$hash" | grep . || echo "$today")" >> "$new_manifest"
done

# Remove o que não está mais no lockfile.
for old in "$mirror"/npm/*.tgz; do
  [[ -e "$old" ]] || continue
  if [[ " ${expected_npm_files[*]} " != *" $(basename "$old") "* ]]; then
    echo "Removendo versão antiga: npm/$(basename "$old")"
    rm -f "$old"
  fi
done
for old in "$mirror"/gems/*/; do
  [[ -e "$old" ]] || continue
  if [[ " ${expected_gem_dirs[*]} " != *" $(basename "$old") "* ]]; then
    echo "Removendo versão antiga: gems/$(basename "$old")"
    rm -rf "$old"
  fi
done

mv "$new_manifest" "$manifest"
echo
echo "Cópia atualizada em vendor/fork-mirror/ ($(du -sh "$mirror" | cut -f1)). MANIFEST.txt:"
cat "$manifest"
echo
echo "Confira com: ops/scripts/use-vendored-packages.sh --check"
