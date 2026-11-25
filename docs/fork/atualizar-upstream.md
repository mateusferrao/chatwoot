# Atualizar para uma nova versão do Chatwoot

O fork mantém o **histórico completo** do upstream. Atualizar é um `git merge` da tag nova, automatizado por [`ops/scripts/sync-upstream.sh`](../../ops/scripts/sync-upstream.sh).

Se o `chatwoot/chatwoot` estiver fora do ar ou tiver sido apagado, use `--source <bundle>` com o espelho guardado nas Releases do nosso repo: `ops/scripts/sync-upstream.sh --source chatwoot-upstream.bundle v4.21.0`. Como obter e conferir o bundle: [`independencia-upstream.md`](independencia-upstream.md).

## Quando atualizar

- Acompanhe as releases em https://github.com/chatwoot/chatwoot/releases.
- **Patches de segurança** (`x.y.Z`): aplique logo.
- **Minors** (`x.Y.0`): leia as release notes. Prefira esperar a primeira correção (`x.Y.1`), a não ser que precise de algo novo.
- Use **sempre tags de release** (`vX.Y.Z`), nunca a branch `develop`.

## Passo a passo

```bash
git checkout main
git pull
ops/scripts/sync-upstream.sh v4.21.0
```

O script:
1. Busca a tag no upstream e cria a branch `sync/upstream-v4.21.0`.
2. Faz o merge. Conflitos previstos se resolvem sozinhos:
   - arquivos que removemos (`ops/upstream-sync/removed-paths.txt`) continuam removidos;
   - arquivos que customizamos (`ops/upstream-sync/ours-paths.txt`) mantêm a versão do fork, e o script avisa para você revisar o que mudou no upstream;
   - arquivos com ajuste **temporário** (`ops/upstream-sync/theirs-paths.txt`, ex.: `Gemfile.lock` com correções de segurança antecipadas) ficam com a versão do upstream. Depois rode `bundle exec bundle-audit check`; se o upstream já incorporou a correção, remova o item da lista.
3. **Regenera o `db/schema.rb`** quando o upstream mexeu em `db/schema.rb` ou `db/migrate` (ou quando o `db/schema.rb` conflitou, o que acontece em quase toda versão nova). Ver [`db/schema.rb` e as tabelas do fork](#dbschemarb-e-as-tabelas-do-fork).
4. Atualiza `ops/UPSTREAM_VERSION` e cria o commit.
5. Imprime um **checklist**: `db/schema.rb` regenerado (revise o diff), migrations novas, mudanças no `.env.example`, workflows novos ou alterados, versões de Ruby/Node.

Saídas do script:
- **0:** merge commitado na branch `sync/upstream-<tag>`.
- **2:** sobrou conflito não previsto. O script lista os arquivos. Resolva e `git add`; se ele avisar que o `db/schema.rb` também precisa ser regenerado, rode `ops/scripts/regenerate-fork-schema.sh <tag>` depois de resolver o resto. Finalize com o commit sugerido.
- **3:** falhou ao regenerar o `db/schema.rb` (Postgres fora do ar, Ruby/gems da versão nova faltando...). O merge fica em andamento, sem commit. Corrija o ambiente, rode `ops/scripts/regenerate-fork-schema.sh <tag>` e faça o commit sugerido.

## `db/schema.rb` e as tabelas do fork

O fork tem migrations próprias (tabelas `automato_agents_*`), listadas em [`ops/upstream-sync/fork-migrations.txt`](../../ops/upstream-sync/fork-migrations.txt). Elas precisam estar no `db/schema.rb`: em banco novo a produção (`db:chatwoot_prepare`) **carrega o `db/schema.rb`** e dá como rodadas todas as migrations com versão até a dele. Uma tabela do fork que sumisse do schema **nunca seria criada**.

Por isso o `db/schema.rb` não é resolvido à mão no merge. O sync chama [`ops/scripts/regenerate-fork-schema.sh <tag>`](../../ops/scripts/regenerate-fork-schema.sh), que:
1. carrega o `db/schema.rb` da tag do upstream num banco descartável (`chatwoot_schema_regen_sync_<pid>_<aleatório>`; o banco do seu ambiente não é alterado: o boot do Rails pode, no máximo, lê-lo);
2. aplica por cima as migrations do fork (desmarcando antes as versões delas, que o `Schema.define` do upstream dá como rodadas);
3. encaixa a diferença (tabelas, chaves estrangeiras e versão) no texto do schema do upstream, para o diff contra o upstream mostrar **só o que é do fork**; confere que o arquivo resultante, carregado num banco limpo, reproduz o banco com as migrations; apaga os bancos descartáveis;
4. roda [`ops/scripts/check-fork-schema.sh`](../../ops/scripts/check-fork-schema.sh) e faz `git add db/schema.rb`.

Requisitos: Ruby/gems do projeto (o script roda `bundle install` se faltar gem da versão nova) e um Postgres com pgvector acessível pela configuração de banco do ambiente (`POSTGRES_HOST`, `POSTGRES_USERNAME`, `POSTGRES_PASSWORD`). Sem Postgres, use `--skip-schema`: o sync avisa em destaque e o `db/schema.rb` fica para resolver antes do PR (com o script acima, em outra máquina, ou à mão conferindo com `check-fork-schema.sh`).

Revise o diff que o checklist indica (`git diff <tag> -- db/schema.rb`): deve mostrar só a linha da versão e as tabelas/chaves `automato_agents_*`. Se o encaixe no texto do upstream conflitar, o script grava o dump completo (correto, mas com diferenças de formatação do dumper local) e avisa.

**Checagem:** `ops/scripts/check-fork-schema.sh` carrega o `db/schema.rb` num banco descartável, desfaz as migrations do fork (falha se a tabela/coluna não existe), refaz e compara o dump com o de antes. Falha também se a versão do schema for anterior a alguma migration do fork, se uma migration listada não existir ou se houver `db/migrate/*automato_agents*` fora da lista. Roda no CI (workflow **Fork - schema do fork**) em PR que toca `db/**` ou `ops/upstream-sync/**`.

**Regra para migrations novas do fork:** toda migration nova do fork entra em `ops/upstream-sync/fork-migrations.txt` (no mesmo PR) e precisa ser reversível (`change` ou `up`/`down`). Use `automato_agents` no nome do arquivo (a checagem pega as esquecidas por esse nome).

Teste de ponta a ponta (pesado, não roda no CI; clona o repo e simula um upstream que conflita no schema):

```bash
eval "$(rbenv init -)"
POSTGRES_PASSWORD=... bash ops/scripts/tests/sync-upstream-schema.test.sh
```

## Checklist de revisão (antes do PR)

- [ ] **Release notes** lidas, especialmente "Breaking changes" e "Upgrade notes".
- [ ] **`db/schema.rb`:** regenerado pelo script e diff contra a tag revisado (só versão e `automato_agents_*`). Se usou `--skip-schema`, rode `ops/scripts/regenerate-fork-schema.sh <tag>` antes do PR.
- [ ] **Migrations novas:** alguma é pesada (índice em tabela grande, backfill)? Se sim, planeje uma janela.
- [ ] **`.env.example`:** variáveis novas que precisam ir para `ops/env/production.env.example` e para o Easypanel.
- [ ] **Workflows novos** do upstream: se forem da operação da Chatwoot Inc., remova e adicione em `removed-paths.txt`.
- [ ] **`enterprise/`:** recursos mudaram de lado? Atualize [`edicao-ce.md`](edicao-ce.md).
- [ ] **Pacotes da Chatwoot Inc.** (`@chatwoot/*`, `ai-agents`, `twitty`) mudaram de versão? Rode `ops/scripts/refresh-vendored-packages.sh` e faça commit de `vendor/fork-mirror/` ([`independencia-upstream.md`](independencia-upstream.md)).
- [ ] **Ruby/Node** mudaram: nada a fazer no servidor (a imagem já traz), mas o ambiente de desenvolvimento precisa acompanhar.

## Publicar

```bash
git push -u origin sync/upstream-v4.21.0
```

1. Abra o PR para `main` com o título `chore(upstream): merge chatwoot v4.21.0`.
2. Espere o CI ficar verde (`run_foss_spec`, `Fork - imagem CE`, `Fork - schema do fork`).
3. Faça o merge e siga "Atualizações" em [`deploy-easypanel.md`](deploy-easypanel.md).
