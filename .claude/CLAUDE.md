# Instruções do fork Automato (complementam o CLAUDE.md/AGENTS.md do upstream)

Este repositório é o fork operacional da Automato do Chatwoot. Leia `FORK.md` antes de qualquer tarefa.

- **Responda e documente em português do Brasil.** Código, nomes de testes e mensagens de log seguem o padrão do upstream (inglês). Docs do fork (`FORK.md`, `docs/fork/`) e mensagens de commit/PR em pt-BR.
- **Edição CE:** nunca edite, copie ou "destrave" código de `enterprise/` (licença proprietária). A pasta só existe para merges limpos e é removida no build (`ops/scripts/strip-enterprise.sh`).
- **Repositório público:** nunca commite segredos (`.env` preenchido, tokens, chaves). Use `ops/env/production.env.example` como referência sem valores.
- **Mínimo de diff no upstream:** customizações vão em arquivos novos (`lib/fork/`, `lib/tasks/fork_*.rake`, `ops/`, `docs/fork/`). Alterou um arquivo do upstream? Registre em `ops/upstream-sync/ours-paths.txt`. Removeu? Registre em `ops/upstream-sync/removed-paths.txt`.
- **Atualizar upstream:** só via `ops/scripts/sync-upstream.sh <tag>` (ver `docs/fork/atualizar-upstream.md`). Nunca rebase/force-push na `main`.
- **Testes locais da CE:** rode em worktree descartável após `ops/scripts/strip-enterprise.sh --confirm`, como faz o CI (`run_foss_spec.yml`).
- **Canal ativo:** só WhatsApp Cloud API. Outros canais estão documentados em `docs/fork/canais-futuros.md`, mas não habilitados.
