# automato_agents

Camada de agentes de IA do fork Automato. Nasce desligada: cada conta precisa ser habilitada em `AutomatoAgents::AccountSetting`.

- **Design:** [`docs/fork/agentes/design.md`](../docs/fork/agentes/design.md). **Plano da Fase 0:** [`docs/fork/agentes/plano-fase-0.md`](../docs/fork/agentes/plano-fase-0.md).
- **Carregamento:** `automato_agents/app/**` e `automato_agents/lib` estão nos `eager_load_paths` (`config/application.rb`), como o `enterprise/`. Não é engine nem gem.
- **Namespace e tabelas:** tudo em `AutomatoAgents::`; tabelas com prefixo `automato_agents_` (`AutomatoAgents.table_name_prefix`).
- **Migrations:** em `db/migrate` do app (geradas com `bundle exec rails g migration`) e refletidas em `db/schema.rb`.
- **Specs:** `spec/automato_agents/`; factories em `spec/factories/automato_agents/`. Rode na worktree CE (`ops/scripts/strip-enterprise.sh --confirm`).
