# Deploy no Easypanel

> **Status: em produção desde 24/11/2026** em `https://crm.automato.pro`. Este documento descreve a instalação **como ela está** e como reproduzi-la ou atualizá-la.

## Arquitetura

O plano do Easypanel permite só 3 projetos, então o Chatwoot roda **dentro do projeto `sites`**, com serviços prefixados `chatwoot-`. Banco e Redis são dedicados; só a rede interna é compartilhada com os outros serviços do projeto.

| Serviço (Easypanel) | Host interno | Imagem | Porta | Exposição |
|---|---|---|---|---|
| `chatwoot-postgres` | `sites_chatwoot-postgres` | `pgvector/pgvector:pg16` | 5432 | **nenhuma** |
| `chatwoot-redis` | `sites_chatwoot-redis` | `redis:7-alpine` (com senha) | 6379 | **nenhuma** |
| `chatwoot-rails` | `sites_chatwoot-rails` | `ghcr.io/mateusferrao/chatwoot:<tag>` | 3000 | `crm.automato.pro` (HTTPS) |
| `chatwoot-sidekiq` | — | mesma imagem e tag do rails | — | nenhuma |

```
Cliente (WhatsApp) ─► Meta ─► https://crm.automato.pro/webhooks/whatsapp/<numero>
                                     │
                         Traefik do Easypanel (TLS)
                                     │
                        chatwoot-rails ──► chatwoot-postgres (pgvector)
                              │      └──► chatwoot-redis ◄── chatwoot-sidekiq
                              └── /app/storage (volume) ◄────── (mesma pasta, bind)
```

Externos (pendentes):
- **AWS S3**: bucket exclusivo para anexos. Enquanto não existe, os anexos ficam no volume do rails (ver "Anexos" abaixo).
- **Amazon SES** (sa-east-1): e-mail de saída via SMTP, domínio `msg.automato.pro` já verificado.

## Imagem

- Gerada pelo workflow **Fork - imagem CE** (GitHub → Actions → *Run workflow* na `main`). Sai como `ghcr.io/mateusferrao/chatwoot:<versão>-ce-<sha>` e `:latest-ce`.
- **Use sempre a tag com sha no Easypanel**, nunca `latest-ce`: deploy reprodutível e rollback fácil.
- O pacote do GHCR é **público**: herda a visibilidade do repositório. O Easypanel baixa sem credenciais; o código é MIT e não há segredo na imagem.
- A imagem traz um **`HEALTHCHECK`** ([`ops/docker/healthcheck.sh`](../../ops/docker/healthcheck.sh)), que serve aos dois processos:
  - **rails:** `GET /api`, com `X-Forwarded-Proto: https` para não cair no redirect do `FORCE_SSL`;
  - **sidekiq:** porta 7433 do `sidekiq_alive`.
  - Com ele, o "zero downtime" do Easypanel/Swarm só troca o container quando o novo está saudável. Sem ele, cada deploy deixava o site fora do ar por ~1–2 min.
  - O `start-period` é de 300 s, porque o boot do rails roda migrations e a task de marca.
- A imagem **não tem `CMD`**: o comando é definido em cada serviço (abaixo).

## Configuração dos serviços

### `chatwoot-rails`
- **Source:** imagem `ghcr.io/mateusferrao/chatwoot:<tag-com-sha>`.
- **Environment:** [`ops/env/production.env.example`](../../ops/env/production.env.example) preenchido, com `POSTGRES_HOST=sites_chatwoot-postgres` e `REDIS_URL=redis://sites_chatwoot-redis:6379`.
- **Deploy → Command:**
  ```
  sh -c "bundle exec rails db:chatwoot_prepare && bundle exec rails fork:branding:apply && bundle exec rails s -p 3000 -b 0.0.0.0"
  ```
  - `db:chatwoot_prepare` carrega o schema na primeira vez e roda as migrations nas seguintes; é idempotente.
  - `fork:branding:apply` aplica a marca a cada deploy; também é idempotente. Fica no comando porque **o Easypanel não executa comandos avulsos em serviços do tipo App** (não há "run command" pela API; só o console web interativo).
- **Mounts:** volume `storage` → `/app/storage`. No host fica em `/var/lib/docker/volumes/sites_chatwoot-rails_storage/_data`.
- **Domains:** `crm.automato.pro` → porta 3000, HTTPS.

### `chatwoot-sidekiq`
- **Source:** mesma imagem e tag do rails.
- **Environment:** **idêntico** ao do rails. Ao mudar uma variável, mude nos dois.
- **Deploy → Command:** `bundle exec sidekiq -C config/sidekiq.yml`
- **Mounts:** *bind* `/var/lib/docker/volumes/sites_chatwoot-rails_storage/_data` → `/app/storage`. É a **mesma pasta** do rails: as mídias do WhatsApp são baixadas pelo sidekiq e servidas pelo rails.

### Marca (logos)
Na edição CE **não existe tela** para nome e logos (o formulário "custom branding" do Super Admin é Enterprise). A task do fork lê:

| Variável | Padrão | Efeito |
|---|---|---|
| `BRAND_NAME` | `Automato` | `INSTALLATION_NAME` e `BRAND_NAME` (dashboard, e-mails, widget) |
| `BRAND_URL` | `https://automato.pro` | `BRAND_URL` e `WIDGET_BRAND_URL` |
| `LOGO_URL`, `LOGO_DARK_URL`, `LOGO_THUMBNAIL_URL` | (não altera) | Logos; o thumbnail (favicon) deve ter 512×512 px |

Para trocar a marca, ajuste essas variáveis no env do `chatwoot-rails` e faça deploy. Os logos precisam de URL pública.

## Primeiro acesso (feito em 24/11/2026)

O onboarding da instalação fica **aberto para quem chegar primeiro** até alguém concluir. Em uma instalação nova:
- Faça o onboarding imediatamente.
- **Desmarque** a newsletter, que envia seus dados de contato à Chatwoot Inc.
- Em "Detalhes da empresa", confira **Idioma = Português Brasileiro (pt-BR)** (sugerido pelo idioma do navegador) e **Fuso = America/Sao_Paulo**.

## Idioma

- A conta criada no onboarding herda `DEFAULT_LOCALE=pt_BR`.
- ⚠️ Ao criar contas **pelo Super Admin** (Accounts → New), selecione **pt_BR** no campo *Locale*: esse formulário não aplica o `DEFAULT_LOCALE` e o padrão do banco é `en`.
- Limitações do upstream: o **Super Admin só existe em inglês**, e o **rodapé dos e-mails** é fixo em inglês ("This email was sent by Automato").

## Pendências

### E-mail (SES SMTP)
1. SES (sa-east-1) → *SMTP settings* → **Create SMTP credentials**. Isso cria um usuário IAM; restrinja a política dele com o JSON abaixo.
2. Nos **dois** serviços, preencha:
   - `SMTP_ADDRESS=email-smtp.sa-east-1.amazonaws.com`
   - `SMTP_USERNAME` e `SMTP_PASSWORD`
3. Deploy dos dois serviços e teste convidando um agente com um e-mail seu.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ses:SendRawEmail",
      "Resource": "arn:aws:ses:sa-east-1:*:identity/msg.automato.pro"
    }
  ]
}
```

### Anexos → S3
1. Crie o bucket (sa-east-1, Block Public Access **ligado**, Versioning ligado) e o usuário IAM `chatwoot-storage`:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       { "Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": "arn:aws:s3:::NOME-DO-BUCKET" },
       { "Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], "Resource": "arn:aws:s3:::NOME-DO-BUCKET/*" }
     ]
   }
   ```
2. Nos dois serviços, preencha `S3_BUCKET_NAME`, `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY`, **mantendo** `ACTIVE_STORAGE_SERVICE=local` por enquanto.
3. Migre os arquivos existentes. No console do `chatwoot-rails`:
   ```
   FROM=local TO=amazon bundle exec rails storage:migrate
   ```
4. Troque para `ACTIVE_STORAGE_SERVICE=amazon` nos dois serviços e faça deploy. Depois de validar, o volume `storage` pode ser esvaziado.

### Backups
- **Postgres:** Easypanel → `chatwoot-postgres` → *Backups* → diário, com destino **externo** (nunca o bucket de anexos), retenção ≥ 14 dias. Teste uma restauração.
- **Segredos:** `SECRET_KEY_BASE` e `ACTIVE_RECORD_ENCRYPTION_*` precisam estar num cofre. Sem eles, um backup do banco não é restaurável por completo, e as chaves de criptografia **nunca** podem mudar.

## Dimensionamento (VPS: 2 vCPU / ~8 GB, compartilhada)

| Serviço | RAM estimada |
|---|---|
| rails (1 processo Puma, 5 threads) | 500–800 MB |
| sidekiq (concorrência 5) | 400–700 MB |
| postgres | 200–400 MB |
| redis | 30–100 MB |

Sinais de que precisa de VPS maior: fila do Sidekiq acumulando (Super Admin → Sidekiq), painel lento, swap em uso.

## Atualizações

1. `ops/scripts/sync-upstream.sh <tag>` → PR → CI verde → merge ([`atualizar-upstream.md`](atualizar-upstream.md)).
2. Actions → **Fork - imagem CE** → *Run workflow* na `main`.
3. **Backup do Postgres** antes de atualizar.
4. Easypanel: troque a tag da imagem no `chatwoot-rails` **e** no `chatwoot-sidekiq` → Deploy. O `db:chatwoot_prepare` aplica as migrations.
5. Rollback: volte a tag anterior. Se a release tinha migrations destrutivas, restaure o backup.
