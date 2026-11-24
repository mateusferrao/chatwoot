# Deploy no Easypanel (blueprint da fase 2)

> **Status: planejado, ainda não executado.** Este documento registra as decisões da fase 1 para o deploy ser mecânico. Revise antes de executar: valores de infraestrutura mudam.

## Arquitetura

Projeto novo no Easypanel: **`chatwoot`** (isolado dos outros sistemas).

| Serviço | Tipo | Imagem | Porta interna | Exposição |
|---|---|---|---|---|
| `postgres` | Postgres | `pgvector/pgvector:pg16` | 5432 | **nenhuma** (só rede interna) |
| `redis` | Redis | `redis:7-alpine` (com senha) | 6379 | **nenhuma** |
| `rails` | App (imagem) | `ghcr.io/mateusferrao/chatwoot:<tag>` | 3000 | domínio `crm.automato.pro` (HTTPS) |
| `sidekiq` | App (imagem) | mesma imagem e tag do `rails` | — | nenhuma |

Externos:
- **AWS S3**: bucket exclusivo para anexos.
- **Amazon SES** (sa-east-1): e-mail de saída via SMTP, domínio `msg.automato.pro` já verificado.

```
Cliente (WhatsApp) ─► Meta ─► https://crm.automato.pro/webhooks/whatsapp/<numero>
                                     │
                         Traefik do Easypanel (TLS)
                                     │
                               chatwoot_rails ──► chatwoot_postgres (pgvector)
                                     │       └──► chatwoot_redis ◄── chatwoot_sidekiq
                                     └──► S3 (anexos)       SES SMTP (e-mails) ◄──┘
```

## Pré-requisitos

1. **Imagem CE publicada:** GitHub → Actions → **Fork - imagem CE** → *Run workflow* na `main`. A imagem sai como `ghcr.io/mateusferrao/chatwoot:<versão>-ce-<sha>` e `:latest-ce`. **Use sempre a tag com sha no Easypanel**, nunca `latest-ce`: deploy reprodutível e rollback fácil.
2. **Acesso do Easypanel ao GHCR:** o pacote do GHCR nasce **privado**. Escolha uma opção:
   - **(a)** GitHub → Packages → `chatwoot` → Package settings → *Change visibility* → **Public**. O código é MIT e o repo já é público, então não há segredo na imagem.
   - **(b)** Manter privado e cadastrar no Easypanel um registry `ghcr.io` com usuário `mateusferrao` e um token (PAT clássico) com escopo **apenas** `read:packages`.
3. **Bucket S3** (região `sa-east-1`, mesma do SES; latência menor para o Brasil):
   - Block Public Access **ligado** (o Chatwoot serve os arquivos por URL assinada).
   - Usuário IAM **exclusivo** `chatwoot-storage` com a política abaixo (troque o nome do bucket).
4. **Credencial SMTP do SES exclusiva:** SES (sa-east-1) → *SMTP settings* → **Create SMTP credentials** (cria o usuário IAM `chatwoot-ses-smtp`). Guarde o usuário e a senha SMTP: a senha só aparece uma vez.
5. **Segredos:** rode `ops/scripts/generate-secrets.sh` e guarde a saída num cofre (1Password, Bitwarden...).

### Política IAM — S3 (usuário `chatwoot-storage`)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::NOME-DO-BUCKET"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::NOME-DO-BUCKET/*"
    }
  ]
}
```

### Política IAM — SES SMTP (usuário criado pelo console)
O console cria com `ses:SendRawEmail` em `*`. Restrinja ao domínio:
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

## Passo a passo

1. **Projeto** `chatwoot` no Easypanel.
2. **Postgres:**
   - Crie o serviço `postgres` (database `chatwoot`, usuário `postgres`, senha gerada).
   - Em *Advanced*, troque a imagem para **`pgvector/pgvector:pg16`**. Sem pgvector o schema não carrega: `enable_extension "vector"`.
   - **Não** preencha *Exposed Port*.
3. **Redis:** crie o serviço `redis` com a senha gerada. Sem *Exposed Port*.
4. **App `rails`:**
   - Source: *Docker Image* → `ghcr.io/mateusferrao/chatwoot:<tag-com-sha>`.
   - Environment: conteúdo de [`ops/env/production.env.example`](../../ops/env/production.env.example) preenchido.
   - Deploy → Command:
     ```
     sh -c "bundle exec rails db:chatwoot_prepare && bundle exec rails s -p 3000 -b 0.0.0.0"
     ```
     O `db:chatwoot_prepare` carrega o schema na primeira vez e roda as migrations nas seguintes; é idempotente. (Geolocalização por IP é opcional: exige `IP_LOOKUP_API_KEY` da MaxMind e `bundle exec rails ip_lookup:setup` antes do servidor.)
   - Domains: `crm.automato.pro` → porta **3000**, HTTPS ligado.
   - Antes, **remova o domínio antigo** `crm.automato.pro` / `www.crm.automato.pro` que ainda aponta para `sites/crm-steticos-front`.
5. **App `sidekiq`:**
   - Mesma imagem e tag, mesmo Environment.
   - Command:
     ```
     bundle exec sidekiq -C config/sidekiq.yml
     ```
   - Sem domínio.
6. **DNS:** confirme que `crm.automato.pro` aponta para o IP da VPS. O registro já existe.
7. **Primeiro acesso:** abra `https://crm.automato.pro`. O Chatwoot mostra o **onboarding da instalação**, onde você cria o **Super Admin** e a primeira conta. Faça isso imediatamente após o deploy, porque até lá a tela fica aberta para quem chegar primeiro.
8. **Marca:**
   ```
   BRAND_NAME="Automato" BRAND_URL="https://automato.pro" bundle exec rails fork:branding:apply
   ```
   Rode no console do serviço `rails`. Depois, no Super Admin → Settings, suba os logos (`LOGO`, `LOGO_DARK`, `LOGO_THUMBNAIL`).
9. **Idioma:** confira em Configurações da conta → Idioma do site = **Português (Brasil)**. Cada agente também pode escolher o idioma no perfil.
10. **WhatsApp:** siga [`whatsapp.md`](whatsapp.md).
11. **Teste de e-mail:** convide um agente com um e-mail seu e confira se o convite chega (remetente `no-reply@msg.automato.pro`).

## Dimensionamento (VPS atual: 2 vCPU / ~8 GB, compartilhada)

| Serviço | RAM estimada |
|---|---|
| rails (1 processo Puma, 5 threads) | 500–800 MB |
| sidekiq (concorrência 5) | 400–700 MB |
| postgres | 200–400 MB |
| redis | 30–100 MB |
| **Total** | **~1,2 a 2 GB** |

- Medição de 24/11/2026: ~4,1 GB livres e ~39 GB de disco livres.
- Configure **limites de memória** nos serviços (Easypanel → Resources) para um vazamento não derrubar os outros sistemas: rails 1 GB, sidekiq 1 GB.
- Sinais de que precisa de VPS maior: fila do Sidekiq acumulando (Super Admin → Sidekiq), respostas lentas no painel, swap em uso.

## Backups

- **Postgres:** Easypanel → serviço `postgres` → *Backups* → diário, com destino **externo** (S3 de backups, nunca o mesmo bucket de anexos), retenção ≥ 14 dias. Teste uma restauração antes de colocar em produção.
- **Anexos:** já ficam no S3. Ative o *Versioning* do bucket para se proteger de exclusão acidental.
- **Segredos:** as chaves `ACTIVE_RECORD_ENCRYPTION_*` e o `SECRET_KEY_BASE` precisam estar no cofre. Sem eles, um backup do banco não é restaurável por completo.

## Atualizações

1. `ops/scripts/sync-upstream.sh <tag>` → PR → CI verde → merge.
2. Actions → **Fork - imagem CE** → *Run workflow* na `main`.
3. Easypanel: troque a tag da imagem no `rails` **e** no `sidekiq` → Deploy. O `db:chatwoot_prepare` aplica as migrations.
4. Rollback: volte a tag anterior. Se a release tinha migrations destrutivas, restaure o backup; por isso, sempre faça backup antes de atualizar.
