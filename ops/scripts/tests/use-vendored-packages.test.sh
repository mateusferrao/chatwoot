#!/usr/bin/env bash
# Teste do ops/scripts/use-vendored-packages.sh (modo de emergência de build).
# Autocontido e offline: monta um projeto sintético em diretório temporário e
# substitui pnpm/bundle por stubs que só registram a chamada.
#
# Uso: bash ops/scripts/tests/use-vendored-packages.test.sh
set -uo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { echo "OK     $1"; }
fail() { echo "FALHOU $1 ($2)"; failures=$((failures + 1)); }
check() { # nome esperado obtido
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "esperado: [$2] obtido: [$3]"; fi
}

# --- projeto sintético ---------------------------------------------------------
make_project() {
  local root="$1" tgz hash
  mkdir -p "$root/ops/scripts/lib" "$root/docker" "$root/bin" \
    "$root/vendor/fork-mirror/npm" \
    "$root/vendor/fork-mirror/gems/ai-agents-0.14.0" "$root/vendor/fork-mirror/gems/twitty-0.1.5"
  cp "$scripts_dir/use-vendored-packages.sh" "$root/ops/scripts/"
  cp "$scripts_dir"/lib/*.sh "$root/ops/scripts/lib/"

  tgz="$root/vendor/fork-mirror/npm/chatwoot-x-1.0.0.tgz"
  echo "conteudo sintetico" > "$tgz"
  hash="sha512-$(openssl dgst -sha512 -binary "$tgz" | base64 | tr -d '\n')"
  : > "$root/vendor/fork-mirror/gems/ai-agents-0.14.0/ai-agents.gemspec"
  : > "$root/vendor/fork-mirror/gems/twitty-0.1.5/twitty.gemspec"
  cat > "$root/vendor/fork-mirror/MANIFEST.txt" <<MANIFEST
# tipo pacote versao origem hash data
npm @chatwoot/x 1.0.0 https://registry.npmjs.org/@chatwoot/x/-/x-1.0.0.tgz $hash 2026-01-01
gem ai-agents 0.14.0 https://rubygems.org/downloads/ai-agents-0.14.0.gem sha256:aaaa 2026-01-01
gem twitty 0.1.5 https://rubygems.org/downloads/twitty-0.1.5.gem sha256:bbbb 2026-01-01
MANIFEST

  cat > "$root/package.json" <<'JSON'
{
  "name": "sintetico",
  "dependencies": {
    "@chatwoot/x": "^1.0.0"
  },
  "pnpm": {
    "overrides": {
      "vite": "6.4.2"
    }
  }
}
JSON
  cat > "$root/pnpm-lock.yaml" <<YAML
lockfileVersion: '9.0'

packages:

  '@chatwoot/x@1.0.0':
    resolution: {integrity: $hash}

snapshots:

  '@chatwoot/x@1.0.0': {}
YAML
  cat > "$root/Gemfile" <<'GEMFILE'
source 'https://rubygems.org'
# gem 'twitty', git: 'https://github.com/chatwoot/twitty'
gem 'twitty', '~> 0.1.5'
gem 'rails'
gem 'ai-agents', '~> 0.14.0'
GEMFILE
  cat > "$root/Gemfile.lock" <<'LOCK'
GEM
  remote: https://rubygems.org/
  specs:
    ai-agents (0.14.0)
    twitty (0.1.5)
LOCK
  cat > "$root/docker/Dockerfile" <<'DOCKERFILE'
FROM ruby:3.4 AS builder
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY package.json pnpm-lock.yaml ./
RUN pnpm i
COPY . /app
DOCKERFILE

  # stubs: registram a chamada e o diretório em que rodaram
  for tool in pnpm bundle; do
    cat > "$root/bin/$tool" <<STUB
#!/usr/bin/env bash
echo "$tool \$*" >> "$root/calls.log"
STUB
    chmod +x "$root/bin/$tool"
  done
}

run() { # raiz args...
  local root="$1"; shift
  (cd "$root" && PATH="$root/bin:$PATH" bash ops/scripts/use-vendored-packages.sh "$@") 2>&1
}

# --- aplicar -------------------------------------------------------------------
p="$work/apply"; make_project "$p"
run "$p" > "$work/apply.out"; status=$?
check "aplicar termina com sucesso" "0" "$status"
check "override novo aponta para o tarball local" \
  "file:vendor/fork-mirror/npm/chatwoot-x-1.0.0.tgz" \
  "$(jq -r '.pnpm.overrides["@chatwoot/x"]' "$p/package.json")"
check "override pré-existente é preservado" "6.4.2" "$(jq -r '.pnpm.overrides.vite' "$p/package.json")"
check "dependências do package.json não mudam" "^1.0.0" "$(jq -r '.dependencies["@chatwoot/x"]' "$p/package.json")"
check "pnpm atualiza só o lockfile" "pnpm install --lockfile-only" "$(grep '^pnpm' "$p/calls.log")"
check "Gemfile: twitty vira path:" "gem 'twitty', path: 'vendor/fork-mirror/gems/twitty-0.1.5'" "$(grep "gem 'twitty'," "$p/Gemfile" | grep -v '^#')"
check "Gemfile: ai-agents vira path:" "gem 'ai-agents', path: 'vendor/fork-mirror/gems/ai-agents-0.14.0'" "$(grep "gem 'ai-agents'" "$p/Gemfile")"
check "Gemfile: demais linhas e comentários ficam" "source 'https://rubygems.org'
# gem 'twitty', git: 'https://github.com/chatwoot/twitty'
gem 'rails'" "$(grep -v "path:" "$p/Gemfile")"
check "bundle relê o lock sem rede" "bundle lock --local" "$(grep '^bundle' "$p/calls.log")"

# --- idempotência --------------------------------------------------------------
run "$p" > /dev/null; status=$?
check "aplicar de novo funciona" "0" "$status"
check "aplicar de novo não duplica linhas do Gemfile" "5" "$(wc -l < "$p/Gemfile" | tr -d ' ')"

# --- --check -------------------------------------------------------------------
p="$work/check"; make_project "$p"
run "$p" --check > "$work/check.out"; status=$?
check "--check passa com a cópia completa" "0" "$status"
check "--check não altera o package.json" "6.4.2" "$(jq -r '.pnpm.overrides.vite' "$p/package.json")"
check "--check não chama pnpm nem bundle" "" "$(cat "$p/calls.log" 2>/dev/null)"
check "--check não altera o Gemfile" "0" "$(grep -c 'path:' "$p/Gemfile")"

rm "$p/vendor/fork-mirror/npm/chatwoot-x-1.0.0.tgz"
run "$p" --check > "$work/check.out"; status=$?
check "--check falha quando falta um tarball" "1" "$status"

p="$work/check-hash"; make_project "$p"
echo "adulterado" > "$p/vendor/fork-mirror/npm/chatwoot-x-1.0.0.tgz"
run "$p" --check > "$work/check.out"; status=$?
check "--check falha quando o tarball não bate com o MANIFEST" "1" "$status"

p="$work/check-gem"; make_project "$p"
rm -r "$p/vendor/fork-mirror/gems/twitty-0.1.5"
run "$p" --check > "$work/check.out"; status=$?
check "--check falha quando falta uma gem" "1" "$status"

p="$work/check-stale"; make_project "$p"
sed -i "s/@chatwoot\/x@1.0.0'/@chatwoot\/x@1.1.0'/" "$p/pnpm-lock.yaml"
run "$p" --check > "$work/check.out"; status=$?
check "--check falha quando o lockfile usa versão diferente da cópia" "1" "$status"

p="$work/check-swapped"; make_project "$p"
echo "tarball trocado" > "$p/vendor/fork-mirror/npm/chatwoot-x-1.0.0.tgz"
new_hash="sha512-$(openssl dgst -sha512 -binary "$p/vendor/fork-mirror/npm/chatwoot-x-1.0.0.tgz" | base64 | tr -d '\n')"
sed -i -E "s|sha512-[^ ]+|$new_hash|" "$p/vendor/fork-mirror/MANIFEST.txt"
sed -i -E "s|integrity: sha512-[^}]+|integrity: sha512-original==|" "$p/pnpm-lock.yaml"
run "$p" --check > "$work/check.out"; status=$?
check "--check falha com tarball trocado e MANIFEST editado para bater (lockfile manda)" "1" "$status"

p="$work/apply-dq"; make_project "$p"
sed -i "s|gem 'twitty', '~> 0.1.5'|gem \"twitty\", '~> 0.1.5'|" "$p/Gemfile"
run "$p" > "$work/apply.out"; status=$?
check "aplicar falha alto quando a linha da gem não usa aspas simples" "1" "$status"
check "aplicar falho não alterou o package.json" "0" "$(grep -c 'file:' "$p/package.json")"

p="$work/apply-missing"; make_project "$p"
rm -r "$p/vendor/fork-mirror/gems/ai-agents-0.14.0"
run "$p" > "$work/apply.out"; status=$?
check "aplicar recusa cópia incompleta" "1" "$status"
check "aplicar recusado não altera o Gemfile" "0" "$(grep -c 'path:' "$p/Gemfile")"

# --- Dockerfile derivado -------------------------------------------------------
p="$work/docker"; make_project "$p"
run "$p" --dockerfile "$p/tmp/Dockerfile.emergencia" > "$work/docker.out"; status=$?
check "--dockerfile termina com sucesso" "0" "$status"
out="$p/tmp/Dockerfile.emergencia"
copy_line="$(grep -n '^COPY vendor/fork-mirror ./vendor/fork-mirror$' "$out" | cut -d: -f1)"
bundle_line="$(grep -n '^RUN bundle install' "$out" | cut -d: -f1)"
pnpm_line="$(grep -n '^RUN pnpm i' "$out" | cut -d: -f1)"
check "uma única linha COPY vendor/fork-mirror" "1" "$(grep -c '^COPY vendor/fork-mirror' "$out")"
if [[ -n "$copy_line" && "$copy_line" -lt "$bundle_line" && "$copy_line" -lt "$pnpm_line" ]]; then
  pass "COPY vendor/fork-mirror vem antes de bundle install e de pnpm i"
else
  fail "COPY vendor/fork-mirror vem antes de bundle install e de pnpm i" "copy=$copy_line bundle=$bundle_line pnpm=$pnpm_line"
fi
check "Dockerfile original não é alterado" "0" "$(grep -c 'vendor/fork-mirror' "$p/docker/Dockerfile")"
check "demais linhas do Dockerfile ficam" "$(wc -l < "$p/docker/Dockerfile" | tr -d ' ')" "$(($(wc -l < "$out" | tr -d ' ') - 1))"

p="$work/docker-anchor"; make_project "$p"
sed -i '/^COPY Gemfile/d' "$p/docker/Dockerfile"
run "$p" --dockerfile "$p/tmp/Dockerfile.emergencia" > "$work/docker.out"; status=$?
check "--dockerfile falha se o Dockerfile mudou e a âncora sumiu" "1" "$status"

echo
if [[ "$failures" -eq 0 ]]; then echo "Todos os testes passaram."; else echo "$failures falha(s)."; exit 1; fi
