# Chatwoot — fork Automato

Este repositório é o **fork operacional da Automato** do [Chatwoot](https://github.com/chatwoot/chatwoot), plataforma open source de atendimento omnichannel. Daqui sai a instalação usada no atendimento da operação, em `https://crm.automato.pro`.

> O `README.md` é o original do upstream e foi mantido sem alterações. Tudo que é específico deste fork está neste arquivo e em [`docs/fork/`](docs/fork/).

## Resumo

| Item | Valor |
|---|---|
| Upstream | `github.com/chatwoot/chatwoot` |
| Versão base | ver [`ops/UPSTREAM_VERSION`](ops/UPSTREAM_VERSION) (inicial: **v4.20.1**) |
| Edição | **Community (CE)**, 100% MIT. Sem código Enterprise em produção |
| Idioma | Português do Brasil (`DEFAULT_LOCALE=pt_BR`) |
| Canal ativo | **WhatsApp oficial** (Cloud API da Meta) |
| Hospedagem | Easypanel (fase 2: [`docs/fork/deploy-easypanel.md`](docs/fork/deploy-easypanel.md)) |
| Imagem Docker | `ghcr.io/mateusferrao/chatwoot` (gerada pelo workflow **Fork - imagem CE**) |

## Regras do fork

1. **Repositório público: nunca commite segredos.** Nada de `.env` preenchido, tokens, chaves ou senhas. O template sem valores está em [`ops/env/production.env.example`](ops/env/production.env.example).
2. **Não edite `enterprise/`.** A pasta continua versionada só para os merges com o upstream ficarem limpos. A licença dela é proprietária, e ela é removida no build da imagem CE ([`ops/scripts/strip-enterprise.sh`](ops/scripts/strip-enterprise.sh)). Detalhes em [`docs/fork/edicao-ce.md`](docs/fork/edicao-ce.md).
3. **Mínimo de alterações em arquivos do upstream.** Customizações vão em arquivos novos (`ops/`, `docs/fork/`, `lib/fork/`, `lib/tasks/fork_*.rake`). Se for inevitável alterar um arquivo do upstream, registre em [`ops/upstream-sync/ours-paths.txt`](ops/upstream-sync/ours-paths.txt). Se remover, registre em [`ops/upstream-sync/removed-paths.txt`](ops/upstream-sync/removed-paths.txt). Ajuste temporário que o upstream deve absorver (ex.: lockfile): [`ops/upstream-sync/theirs-paths.txt`](ops/upstream-sync/theirs-paths.txt).
4. **Fluxo de branches:**
   - `main` é o que vai para produção. Só recebe código por Pull Request.
   - Features e ajustes: branch própria → PR para `main`.
   - Atualização do upstream: `sync/upstream-<tag>` gerada pelo script → PR para `main` ([`docs/fork/atualizar-upstream.md`](docs/fork/atualizar-upstream.md)).
5. **Títulos de PR em Conventional Commits** (`feat: …`, `fix: …`, `chore: …`, `docs: …`). O workflow `lint_pr.yml` do upstream valida isso.

## O que mudou em relação ao upstream

| Mudança | Por quê |
|---|---|
| Removidos 8 workflows (`deploy_check`, `ghsa-linear-sync`, `lock`, `nightly_installer`, `publish_codespace_image`, `publish_ee_docker`, `publish_foss_docker`, `stale`), `FUNDING.yml` e `.dependabot/` | Eram da operação da Chatwoot Inc. (DockerHub, Linear, review apps Heroku) e aqui falhariam ou agiriam sobre nossas issues |
| `CODEOWNERS` → `@mateusferrao` | O original apontava para funcionários da Chatwoot Inc. |
| Workflow **Fork - imagem CE** | Gera a imagem CE no GitHub Actions, já que a VPS não comporta o build |
| `Gemfile.lock`: `puma` 7.2.3 e `rack-protection` 4.2.2 | Correções de segurança apontadas pelo `bundle-audit` e publicadas depois da v4.20.1. O `develop` do upstream já tem as mesmas versões; registrado em `ops/upstream-sync/theirs-paths.txt` |
| `rails fork:branding:apply` ([`lib/fork/branding.rb`](lib/fork/branding.rb)) | Aplica nome, URL e logos da Automato (na CE não há tela para isso) e remove o "Powered by" do widget e da central de ajuda |
| `ops/` e `docs/fork/` | Ferramentas e documentação próprias do fork |

Testes e lint do upstream continuam ativos: `run_foss_spec.yml` roda a suíte da edição CE em todo PR.

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/fork/edicao-ce.md`](docs/fork/edicao-ce.md) | O que a edição CE não tem, o que é permitido fazer e as alternativas |
| [`docs/fork/whatsapp.md`](docs/fork/whatsapp.md) | WhatsApp oficial: setup manual e Embedded Signup |
| [`docs/fork/deploy-easypanel.md`](docs/fork/deploy-easypanel.md) | Blueprint do deploy no Easypanel (fase 2) |
| [`docs/fork/atualizar-upstream.md`](docs/fork/atualizar-upstream.md) | Como trazer novas versões do Chatwoot |
| [`docs/fork/canais-futuros.md`](docs/fork/canais-futuros.md) | Instagram/Facebook, e-mail e widget (planejados, não ativos) |

## Comandos úteis

```bash
# Gerar segredos para um ambiente novo (só imprime, não grava)
ops/scripts/generate-secrets.sh

# Trazer uma versão nova do Chatwoot
ops/scripts/sync-upstream.sh v4.21.0

# Aplicar a marca (no container, depois do primeiro deploy; LOGO_* são opcionais)
BRAND_NAME="Automato" BRAND_URL="https://automato.pro" LOGO_URL="https://.../logo.svg" bundle exec rails fork:branding:apply
```
