# Independência do upstream

Runbook: o que o fork já tem de proteção caso o `chatwoot/chatwoot` seja apagado ou reescrito, como usar o espelho e o que fazer se isso acontecer.

## O que está protegido e por quê

| Dependência | Situação | Efeito se o upstream sumir |
|---|---|---|
| Repositório Git | `mateusferrao/chatwoot` **não é um fork no GitHub** (`fork:false`) e tem o **histórico completo** do upstream | Nada muda no nosso repositório |
| Imagens Docker | Ficam no GHCR do nosso repositório (`ghcr.io/mateusferrao/chatwoot`); as bases `node`/`ruby` vêm do Docker Hub | Imagens já publicadas continuam rodando. **Não apague** as publicadas |
| `ChatwootHub` ([`lib/chatwoot_hub.rb`](../../lib/chatwoot_hub.rb)) | Ping de versão, registro e push relay têm `rescue` em todas as chamadas | Hub fora do ar não derruba o sistema |
| Push para os apps móveis oficiais | Os apps são da Chatwoot Inc. e o push passa pelo hub deles | O push para esses apps para. O atendimento pelo navegador não depende deles. Para parar de tentar o relay: `ENABLE_PUSH_RELAY_SERVER=false` |
| Atualizações | `ops/scripts/sync-upstream.sh` busca no `chatwoot/chatwoot` | Use o espelho (próxima seção) |
| Pacotes npm e gems da Chatwoot Inc. | Ver "Pacotes publicados pela Chatwoot Inc." | Build de imagem nova pode quebrar |

## O espelho do upstream

O workflow **Fork - espelho do upstream** (`.github/workflows/fork-upstream-mirror.yml`) guarda uma cópia do upstream como **git bundle**:

- **O que guarda:** as branches `develop` e `master` e todas as tags. Não inclui `refs/pull/*`.
- **Onde:** na aba Releases do nosso repositório, como pré-lançamento (não "latest") com tag `upstream-mirror-AAAA-MM-DD` (`-2`, `-3`... se houver mais de uma no mesmo dia). Cada Release tem três arquivos: `chatwoot-upstream.bundle`, `manifest.txt` e `SHA256SUMS`.
- **Quando roda:** toda segunda-feira às 05:23 UTC e sob demanda. Para rodar agora: Actions → **Fork - espelho do upstream** → **Run workflow**.
- **Retenção:** as **8** Releases `upstream-mirror-*` mais recentes. As mais antigas são apagadas junto com a tag. Releases com outros nomes nunca são tocadas.
- **Se o fetch falhar:** o job fica vermelho e as Releases existentes não mudam.

Para conferir uma Release, abra o `manifest.txt` (data UTC, SHA de `develop` e `master`, tag `vX.Y.Z` mais recente, número de tags, tamanho do bundle) e valide o bundle com `SHA256SUMS`, como no passo a passo abaixo.

## Atualizar a partir do espelho

```bash
# 1. Baixar a Release do espelho (escolha a data mais recente)
gh release download upstream-mirror-AAAA-MM-DD -R mateusferrao/chatwoot
#    ou baixe os três arquivos pelo link da Release no GitHub

# 2. Conferir a integridade
sha256sum -c SHA256SUMS

# 3. Atualizar (a partir de uma main limpa e atualizada)
git checkout main && git pull
ops/scripts/sync-upstream.sh --source chatwoot-upstream.bundle vX.Y.Z
```

O script verifica o bundle (`git bundle verify`), busca nele a tag e a versão atual, e segue o fluxo normal, sem criar nem alterar o remote `upstream`. O restante (conflitos previstos, checklist, PR) está em [`atualizar-upstream.md`](atualizar-upstream.md). `--source` também aceita uma URL git, caso exista outra cópia do repositório.

## Pacotes publicados pela Chatwoot Inc.

O build da imagem baixa pacotes que a Chatwoot Inc. publica. Se forem despublicados, **o build de uma imagem nova quebra** (imagens já publicadas continuam rodando). Por isso o repositório guarda uma cópia das versões exatas em [`vendor/fork-mirror/`](../../vendor/fork-mirror/):

- `npm/`: os 7 pacotes `@chatwoot/*` do `pnpm-lock.yaml` (`captain-avatar`, `jumpbar`, `ninja-keys`, `pico-search`, `prosemirror-schema`, `utils`, `viz`), como tarballs.
- `gems/`: `ai-agents` e `twitty` do `Gemfile.lock`, desempacotadas, com `.gemspec`.
- `MANIFEST.txt`: pacote, versão, origem e hash conferido (sha512 do `pnpm-lock.yaml` para npm; sha256 da API do RubyGems para gems).

Todos são MIT. **Por padrão nada muda no build:** a cópia só é usada no modo de emergência.

### Atualizar a cópia

Depois de qualquer mudança de versão desses pacotes (por exemplo, ao atualizar o upstream):

```bash
ops/scripts/refresh-vendored-packages.sh     # lê as versões dos lockfiles, baixa, confere o hash e remove versões antigas
ops/scripts/use-vendored-packages.sh --check # confere se a cópia bate com o MANIFEST e com os lockfiles
git add vendor/fork-mirror && git commit
```

O script de refresh **falha** se o hash baixado não bater com o do lockfile (npm) ou com o do RubyGems (gems), e não grava nada nesse caso. Rodar de novo sem mudanças não gera diff.

### Ativar o modo de emergência

Use quando o npm ou o RubyGems não entregarem mais esses pacotes. Faça numa **branch de emergência**; a `main` não muda.

```bash
git checkout -b emergencia/pacotes-locais
ops/scripts/use-vendored-packages.sh --dockerfile tmp/Dockerfile.emergencia
```

O script, a partir de `vendor/fork-mirror/`:

1. escreve em `package.json` → `pnpm.overrides` uma entrada `"@chatwoot/<nome>": "file:vendor/fork-mirror/npm/..."` por pacote (mantendo os overrides existentes) e roda `pnpm install --lockfile-only`;
2. troca no `Gemfile` as linhas de `ai-agents` e `twitty` por `gem '<nome>', path: 'vendor/fork-mirror/gems/<nome>-<versão>'` e roda `bundle lock --local`;
3. gera `tmp/Dockerfile.emergencia`, uma cópia do `docker/Dockerfile` com `COPY vendor/fork-mirror ./vendor/fork-mirror` antes do `bundle install` e do `pnpm i` (o Dockerfile só copia `Gemfile*` e `package.json`/lockfile nessa etapa, e o `path:`/`file:` precisa da pasta). O `docker/Dockerfile` do upstream não é alterado.

Revise o diff (`git diff package.json Gemfile Gemfile.lock`), faça commit e abra um PR. Para gerar a imagem, use o `tmp/Dockerfile.emergencia` no lugar do `docker/Dockerfile` (é o que o job de prova faz; veja abaixo). Precisa de Ruby, `pnpm` e das gems instaladas localmente (`bundle lock --local` não acessa a rede). `use-vendored-packages.sh --check` só confere, sem alterar nada.

### Provar que funciona (job de emergência)

O workflow **Fork - imagem CE** tem o job **Build com pacotes da Chatwoot indisponíveis**. Ele aplica o modo de emergência, bloqueia o escopo `@chatwoot` do npm (`@chatwoot:registry=http://127.0.0.1:9/`, inclusive dentro do build da imagem), confere que `ai-agents` e `twitty` estão em seções `PATH` do `Gemfile.lock` e compila a imagem, **sem publicar**. Roda:

- automaticamente em PR que altera `vendor/fork-mirror/**` ou os scripts `*vendored*`;
- manualmente: Actions > **Fork - imagem CE** > Run workflow com **testar_emergencia** marcado. Atenção: o disparo manual também roda o job `build` normal, que publica a imagem como sempre.

Rode esse job de tempos em tempos (e após atualizar o upstream) para garantir que o plano B continua funcionando. O teste local do script (`bash ops/scripts/tests/use-vendored-packages.test.sh`) é offline.

## Se o upstream sumir hoje

1. **Não apague nada nosso:** imagens no GHCR, Releases `upstream-mirror-*` e o repositório. Produção continua rodando como está.
2. Confirme que há uma Release `upstream-mirror-*` recente. Se o upstream ainda responde, rode o workflow do espelho agora.
3. Baixe o bundle e confira com `sha256sum -c SHA256SUMS`. Guarde uma cópia fora do GitHub (disco local ou storage da Automato).
4. Para novas versões, não haverá mais releases oficiais: a base passa a ser o último bundle. Qualquer correção nova entra por commits nossos.
5. Faça um build de imagem de teste (**Fork - imagem CE**) para saber se os pacotes `@chatwoot/*`, `ai-agents` e `twitty` ainda são baixáveis. Se não forem, ative o modo de emergência (seção acima).
6. Se o `ChatwootHub` estiver inacessível e os logs ruidosos, defina `ENABLE_PUSH_RELAY_SERVER=false`. Avise a equipe que o push dos apps móveis oficiais parou.
