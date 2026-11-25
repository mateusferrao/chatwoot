# vendor/fork-mirror

Cópia dos pacotes que a Chatwoot Inc. publica no npm e no RubyGems e que o build da imagem usa. Serve só para o **modo de emergência** (se esses pacotes forem despublicados). No build normal, esta pasta não é usada.

- `npm/`: tarballs exatos dos pacotes `@chatwoot/*` do `pnpm-lock.yaml`.
- `gems/`: as gems `ai-agents` e `twitty` do `Gemfile.lock`, já desempacotadas (com o `.gemspec`) para o Bundler usar como `path:`.
- `MANIFEST.txt`: pacote, versão, origem e hash conferido de cada item.

Todos os pacotes são MIT (a licença acompanha cada pacote). **Não edite à mão:** gere com `ops/scripts/refresh-vendored-packages.sh`. Como usar: [`docs/fork/independencia-upstream.md`](../../docs/fork/independencia-upstream.md).

## Observações

- As gems em `gems/` são cópias **fiéis** do conteúdo do `.gem`. Contêm arquivos inertes (`CLAUDE.md` e `Gemfile.lock` aninhados, um workflow em `.github/` no `twitty`) que **não devem ser editados nem podados**: qualquer edição quebra a fidelidade com o original.
- A origem das gems só é verificada contra o rubygems.org (sha256 da API), pois o `Gemfile.lock` não tem seção `CHECKSUMS`. Para os pacotes npm vale o `integrity` do `pnpm-lock.yaml`.
