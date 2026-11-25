#!/usr/bin/env bash
# Funções compartilhadas por refresh-vendored-packages.sh e use-vendored-packages.sh.
# Não é executável: use com `source`. Espera que $repo_root já esteja definido.

# Gems publicadas pela Chatwoot Inc. que o build baixa do RubyGems.
VENDORED_GEMS=(ai-agents twitty)

mirror_dir() { echo "$repo_root/vendor/fork-mirror"; }

# Lê do pnpm-lock.yaml (seção packages:) os pacotes @chatwoot/*.
# Saída, uma linha por pacote: <nome-sem-escopo> <versão> <integrity sha512>
# Entradas que não são versão do registro (ex.: file:, com o modo de emergência aplicado) são ignoradas.
lockfile_npm_packages() {
  awk '
    /^packages:/ { in_packages = 1; next }
    /^[^ ]/ { in_packages = 0 }
    in_packages && /^  \x27@chatwoot\/[^@]+@[^\x27]+\x27:$/ {
      key = $0
      gsub(/^  \x27|\x27:$/, "", key)
      split(key, parts, "@")
      name = parts[2]; sub(/^chatwoot\//, "", name)
      version = parts[3]
      pending = (version ~ /^[0-9]/)
      next
    }
    pending && /resolution: \{integrity:/ {
      integrity = $0
      sub(/.*integrity: */, "", integrity); sub(/[,}].*/, "", integrity)
      print name, version, integrity
      pending = 0
    }
  ' "$repo_root/pnpm-lock.yaml"
}

# Lê do Gemfile.lock a versão de uma gem. Saída vazia se não houver.
lockfile_gem_version() {
  local gem_name="$1"
  sed -n "s/^    ${gem_name} (\([0-9][^)]*\))$/\1/p" "$repo_root/Gemfile.lock" | head -n 1
}

# sha512 de um arquivo no formato "integrity" do npm (sha512-<base64>).
npm_integrity_of() {
  echo "sha512-$(openssl dgst -sha512 -binary "$1" | base64 | tr -d '\n')"
}

npm_tarball_name() { echo "chatwoot-$1-$2.tgz"; }   # <nome> <versão>
gem_dir_name() { echo "$1-$2"; }                      # <gem> <versão>

# Linhas do MANIFEST.txt (sem comentários): tipo pacote versão origem hash data
manifest_entries() {
  grep -v '^#' "$(mirror_dir)/MANIFEST.txt" | grep -v '^[[:space:]]*$'
}
