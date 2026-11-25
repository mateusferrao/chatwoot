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
3. Atualiza `ops/UPSTREAM_VERSION` e cria o commit.
4. Imprime um **checklist**: migrations novas, mudanças no `.env.example`, workflows novos ou alterados, versões de Ruby/Node.

Se sobrar conflito não previsto, o script para (saída 2) e lista os arquivos. Resolva, `git add` e finalize com o commit sugerido.

## Checklist de revisão (antes do PR)

- [ ] **Release notes** lidas, especialmente "Breaking changes" e "Upgrade notes".
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
2. Espere o CI ficar verde (`run_foss_spec`, `Fork - imagem CE`).
3. Faça o merge e siga "Atualizações" em [`deploy-easypanel.md`](deploy-easypanel.md).
