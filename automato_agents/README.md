# automato_agents

Camada de agentes de IA do fork Automato. Nasce desligada: cada conta precisa ser habilitada em `AutomatoAgents::AccountSetting`.

- **Design:** [`docs/fork/agentes/design.md`](../docs/fork/agentes/design.md). **Plano da Fase 0:** [`docs/fork/agentes/plano-fase-0.md`](../docs/fork/agentes/plano-fase-0.md).
- **Carregamento:** `automato_agents/app/**` e `automato_agents/lib` estão nos `eager_load_paths` (`config/application.rb`), como o `enterprise/`. Não é engine nem gem.
- **Namespace e tabelas:** tudo em `AutomatoAgents::`; tabelas com prefixo `automato_agents_` (`AutomatoAgents.table_name_prefix`).
- **Migrations:** em `db/migrate` do app (geradas com `bundle exec rails g migration`, com `automato_agents` no nome) e refletidas em `db/schema.rb`. **Toda migration nova do fork entra em [`ops/upstream-sync/fork-migrations.txt`](../ops/upstream-sync/fork-migrations.txt)** e precisa ser reversível: é com essa lista que o sync do upstream regenera o `db/schema.rb` com as nossas tabelas e que `ops/scripts/check-fork-schema.sh` (também no CI) confere o schema ([`docs/fork/atualizar-upstream.md`](../docs/fork/atualizar-upstream.md#dbschemarb-e-as-tabelas-do-fork)).
- **Specs:** `spec/automato_agents/`; factories em `spec/factories/automato_agents/`. Rode na worktree CE (`ops/scripts/strip-enterprise.sh --confirm`).
- **Super Admin:** *Contas com agentes de IA* (liga o módulo da conta e configura modelos, mensagens e orçamento) e *Equipes de agentes* (conta, inboxes, ligada). Controllers em `app/controllers/super_admin/automato_agents/`, dashboards em `app/dashboards/automato_agents/`, campo de inboxes em `app/fields/` com parciais em `app/views/fields/` (essa pasta de views só entra no lookup desses controllers e não é varrida pelo Tailwind: use só classes que já aparecem em `app/views`). Textos em `config/locales/automato_agents.{en,pt_BR}.yml`.
