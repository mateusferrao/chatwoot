# Fase 0 (fundação) — plano de implementação

> **Para agentes:** executar com superpowers:subagent-driven-development (uma fatia por vez: implementador novo → revisão independente → correções → merge). Passos em checkbox.

**Objetivo:** ter a base da camada de agentes rodando em produção, desligada por padrão: equipe ligada a inboxes via AgentBot, ponte de eventos, porta de IA com custo registrado, um agente "eco" de ponta a ponta, pausa por humano, orçamento e telas mínimas no Super Admin.

**Arquitetura:** código próprio no diretório `automato_agents/` (namespace `AutomatoAgents::`), carregado como o `enterprise/` é carregado (`config/application.rb`). Migrations no `db/migrate` do app. Execução em fila Sidekiq própria (`automato_agents`) processada por um serviço separado.

**Stack:** Rails 8.0 (load_defaults 7.0, Zeitwerk), Sidekiq, Postgres, Redis, `ruby_llm` 2.1.1 (OpenRouter), `ai-agents` 0.14.0. Sem dependências novas.

**Spec:** [`docs/fork/agentes/design.md`](design.md). Fatos de código levantados para este plano estão citados em cada tarefa.

## Desvios do design (decididos neste plano)

| Design dizia | Plano faz | Por quê |
|---|---|---|
| "engine Rails isolada" em `engines/automato_agents`, gem por path | Diretório `automato_agents/` (app/, lib/) adicionado aos `eager_load_paths` em `config/application.rb`, como o `enterprise/` | Gem por path exige mexer no `Gemfile` **e** no `Gemfile.lock` (este está em `theirs-paths.txt`, sobrescrito a cada sync). Migrations de engine não entram sozinhas no `db:migrate`/`db:chatwoot_prepare` (railtie do ActiveRecord só as inclui com `ENGINE_ROOT`) e as tabelas precisam estar no `db/schema.rb` de qualquer forma. Mesmo isolamento de código com 1 linha de diff no upstream |
| Migrations da engine | `db/migrate` do app, geradas com `bundle exec rails g migration` | `db:chatwoot_prepare` carrega `schema.rb` e marca migrations antigas como rodadas; `migration_version_check.yml` valida `db/migrate/**` |
| SSRF própria e credenciais criptografadas na Fase 0 (0.7) | Movidas para a fatia 1.7 (ferramentas HTTP), onde são usadas pela primeira vez | YAGNI: na Fase 0 nada chama URL configurável nem guarda credencial (a chave OpenRouter fica em variável de ambiente) |
| — | Nova fatia 0.8: telas mínimas no Super Admin (configuração da conta e equipes) | Sem elas não há como ligar o módulo em produção (o Easypanel não executa comandos em serviços App) |

## Restrições globais

- Namespace `AutomatoAgents`; tabelas com prefixo `automato_agents_` (via `AutomatoAgents.table_name_prefix`).
- Nunca editar `enterprise/`. Todo arquivo do upstream alterado entra em `ops/upstream-sync/ours-paths.txt`.
- Specs em `spec/automato_agents/` (o CI `run_foss_spec.yml` só procura em `spec/`). Rodar na worktree CE (`ops/scripts/strip-enterprise.sh --confirm`).
- Fila Sidekiq `automato_agents` **não** entra em `config/sidekiq.yml`: é processada só pelo serviço `chatwoot-agents` (`bundle exec sidekiq -q automato_agents -c 3`).
- Tudo nasce **desligado**: `AccountSetting#enabled` e `Team#enabled` padrão `false`.
- IA: OpenRouter via `RubyLLM.context` (nunca configuração global; a global é do núcleo, `config/initializers/ai_agents.rb`). Chave em `AUTOMATO_AGENTS_OPENROUTER_API_KEY`. Modelo padrão: `google/gemini-3.1-flash-lite`; modelo econômico padrão: `google/gemini-2.5-flash-lite`.
- Textos para o cliente final em pt-BR, guardados em configuração (não fixos no código), com padrão pt-BR.
- RuboCop/CLAUDE.md do upstream: sem `Thread.new`, sem SQL cru, métodos multilinha, sem métodos "endless".
- Commits em pt-BR, Conventional Commits, rodapé de coautoria da sessão.

## Review Focus

1. **Loop do bot consigo mesmo:** mensagens enviadas pelo próprio bot (outgoing, `AgentBot`) disparam `message.created`. Nunca podem agendar turno nem pausar o agente. (Teste em 0.3 e 0.6.)
2. **Conversa fora do bot:** mensagem recebida em conversa `open` (humano assumiu), `resolved` ou de inbox sem equipe não pode acionar o agente. (Teste em 0.3.)
3. **Rajada + concorrência:** 3 mensagens em 2 s → um único turno, que responde considerando as 3; dois jobs simultâneos da mesma conversa nunca rodam ao mesmo tempo. (Teste em 0.3 e 0.5.)
4. **Falha do provedor de IA ou chave ausente:** o cliente final recebe a mensagem padrão e a conversa vai para humano; nada fica "pendente para sempre". (Teste em 0.5.)
5. **Orçamento estourado no meio do mês:** com política "humano", nenhuma chamada de IA é feita. (Teste em 0.7.)

---

### Fatia 0.1 — Esqueleto + configuração da conta

**Arquivos:**
- Modificar: `config/application.rb` (após a linha do `enterprise/app/**`): `config.eager_load_paths += Dir["#{Rails.root}/automato_agents/app/**"]` e `config.eager_load_paths << Rails.root.join('automato_agents/lib')`.
- Criar: `automato_agents/app/models/automato_agents.rb` (módulo com `table_name_prefix` → `'automato_agents_'`), `automato_agents/app/models/automato_agents/account_setting.rb`, `automato_agents/README.md` (curto, pt-BR).
- Migration: `CreateAutomatoAgentsAccountSettings` — `account_id` (bigint, not null, índice único, FK `accounts` com `on_delete: :cascade`), `enabled` (boolean, not null, default false), `default_model` (string, not null, default `'google/gemini-3.1-flash-lite'`), `fallback_message` (text, not null, default `'Desculpe, tive um problema por aqui. Vou te passar para alguém da nossa equipe.'`), timestamps.
- Modificar: `ops/upstream-sync/ours-paths.txt` (+ `config/application.rb`), `docs/fork/agentes/design.md` seção 5 (trocar "engine em `engines/`" pela decisão deste plano), `FORK.md` (tabela "O que mudou").
- Testes: `spec/automato_agents/models/account_setting_spec.rb`, `spec/factories/automato_agents/account_settings.rb`.

**Interfaces produzidas:**
- `AutomatoAgents::AccountSetting.for(account) -> AccountSetting` (find_or_initialize; não salva).
- `AutomatoAgents.enabled_for?(account) -> Boolean` (`AccountSetting` existe e `enabled`).

- [ ] Teste: `for(account)` devolve registro novo desligado com os padrões acima; único por conta (validação + índice); `enabled_for?` falso sem registro e quando `enabled: false`, verdadeiro com `enabled: true`; ao apagar a conta, o setting some.
- [ ] RED → implementar → GREEN.
- [ ] Verificar boot: `bundle exec rails runner 'puts AutomatoAgents::AccountSetting.table_name'` → `automato_agents_account_settings`; `bundle exec rails zeitwerk:check` sem erros.
- [ ] `db/schema.rb` atualizado pela migration; commit.

### Fatia 0.2 — Equipe + AgentBot ligado às inboxes

**Arquivos:**
- Migrations: `CreateAutomatoAgentsTeams` — `account_id` (FK cascade), `name` (string, not null), `enabled` (bool, not null, default false), `agent_bot_id` (FK `agent_bots`, nullable, `on_delete: :nullify`), timestamps; índice `[account_id, name]` único. `CreateAutomatoAgentsTeamInboxes` — `team_id` (FK cascade), `inbox_id` (FK cascade, **índice único**: uma inbox pertence a no máximo uma equipe), timestamps.
- Criar: `automato_agents/app/models/automato_agents/team.rb`, `.../team_inbox.rb`, `automato_agents/app/services/automato_agents/teams/provision_service.rb`.
- Testes: `spec/automato_agents/models/team_spec.rb`, `spec/automato_agents/services/teams/provision_service_spec.rb`, factories.

**Interfaces:**
- Consome: `AgentBot` (`account.agent_bots.create!(name:, description:, bot_config:)`; só valida tamanho de `outgoing_url`), `AgentBotInbox` (`inbox.agent_bot_inbox || AgentBotInbox.new(inbox:)`, status `active`; falha se Dialogflow ativo na inbox), padrão de `inboxes_controller#set_agent_bot`.
- Produz: `AutomatoAgents::Teams::ProvisionService.new(team).perform` — garante o AgentBot da equipe (`outgoing_url` vazio, `description` `'Automato Agents'`, `bot_config: { 'automato_agents_team_id' => team.id }`), liga cada inbox da equipe (AgentBotInbox `active`) e desliga (`destroy`) AgentBotInbox de inboxes removidas que apontavam para o bot da equipe. Idempotente. `Team#active?` = `enabled && AutomatoAgents.enabled_for?(account)`. `Team.for_inbox(inbox) -> Team | nil`.

- [ ] Teste: provisionar cria 1 AgentBot por equipe (idempotente ao rodar 2x); conversa nova numa inbox ligada nasce `pending` com `assignee_agent_bot_id == team.agent_bot_id`; **nenhuma requisição HTTP** é feita ao criar mensagem (WebMock estrito); remover inbox da equipe e reprovisionar remove o vínculo; inbox com Dialogflow ativo → erro de validação propagado; inbox de outra conta → inválido.
- [ ] RED → implementar → GREEN → commit.

### Fatia 0.3 — Ponte de eventos, debounce e trava

**Arquivos:**
- Criar: `config/initializers/automato_agents.rb` (arquivo novo; ordem alfabética garante o `to_prepare` antes do `event_handlers.rb`): `Rails.application.config.to_prepare { AsyncDispatcher.prepend(AutomatoAgents::AsyncDispatcherExtension) }`.
- Criar: `automato_agents/app/dispatchers/automato_agents/async_dispatcher_extension.rb` (`def listeners; super + [AutomatoAgents::EventListener.instance]; end`), `automato_agents/app/listeners/automato_agents/event_listener.rb` (`< BaseListener`), `automato_agents/app/services/automato_agents/turn_scheduler.rb`, `automato_agents/app/jobs/automato_agents/turn_job.rb` (`queue_as :automato_agents`), `automato_agents/app/services/automato_agents/turn.rb`.
- Testes: `spec/automato_agents/listeners/event_listener_spec.rb`, `spec/automato_agents/services/turn_scheduler_spec.rb`, `spec/automato_agents/jobs/turn_job_spec.rb`, `spec/automato_agents/dispatchers/async_dispatcher_extension_spec.rb`.

**Interfaces:**
- Consome: `BaseListener` (método `message_created(event)`, `event.data[:message]`; o evento sai de `after_create_commit` e chega via `EventDispatcherJob`), `Redis::Alfred` (`setex`, `get`), `Redis::LockManager#with_lock(key, timeout)`.
- Produz:
  - `EventListener#message_created(event)`: agenda turno quando **todas**: mensagem `incoming`, não privada; conversa `pending`; `conversation.assignee_agent_bot_id` = bot de uma equipe `active?` dessa inbox; estado da conversa não pausado (0.6). Caso contrário, ignora.
  - `TurnScheduler.schedule(conversation)`: grava token aleatório em `AUTOMATO_AGENTS::TURN_TOKEN::<conversation_id>` (`setex`, TTL 600 s) e enfileira `TurnJob.set(wait: 4.seconds).perform_later(conversation.id, token)`.
  - `TurnJob#perform(conversation_id, token)`: descarta se o token atual ≠ `token` (mensagem mais nova vai gerar outro job); senão `Redis::LockManager.new.with_lock("AUTOMATO_AGENTS::TURN_LOCK::#{id}", 180)` { `AutomatoAgents::Turn.new(conversation).perform` }; se a trava não foi obtida, reenfileira com `wait: 5.seconds` mantendo o token.
  - `Turn#perform`: nesta fatia só registra no log `[AutomatoAgents] turno conversation=<id>`; implementação real em 0.5.

- [ ] Testes: listener registrado (`Rails.configuration.dispatcher.async_dispatcher.listeners` inclui a instância); 3 mensagens incoming seguidas → 3 jobs enfileirados mas só o último token executa `Turn#perform` (1 vez); mensagem outgoing do bot, privada, de contato em conversa `open`/`resolved`, de inbox sem equipe, de equipe desligada ou conta desligada → nada agendado; trava ocupada → job reenfileirado e `Turn#perform` não chamado.
- [ ] RED → implementar → GREEN → commit.

### Fatia 0.4 — Porta de IA (OpenRouter) + ledger de uso

**Arquivos:**
- Migration: `CreateAutomatoAgentsUsageEntries` — `account_id` (FK cascade, índice `[account_id, created_at]`), `team_id` (nullable), `conversation_id` (nullable), `provider` (string, not null), `model` (string, not null), `kind` (string, not null: `chat`|`embedding`|`transcription`|`vision`), `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`, `thinking_tokens` (integer, default 0), `cost_usd` (decimal 14,8, nullable), `cost_source` (string, not null: `reported`|`estimated`|`unknown`), `key_source` (string, not null, default `'automato'`), `created_at`.
- Criar: `automato_agents/app/models/automato_agents/usage_entry.rb`, `automato_agents/lib/automato_agents/llm/open_router_provider.rb`, `automato_agents/lib/automato_agents/llm/errors.rb`, `automato_agents/app/services/automato_agents/usage/recorder.rb`.
- Testes: `spec/automato_agents/lib/llm/open_router_provider_spec.rb`, `spec/automato_agents/services/usage/recorder_spec.rb`.

**Interfaces:**
- Consome: `RubyLLM.context { |c| c.openrouter_api_key = …; c.openrouter_app_name = 'Automato Agents'; c.openrouter_app_url = ENV['FRONTEND_URL'] }`; `ctx.chat(model:, provider: :openrouter, assume_model_exists: true)`; `Chat#with_context(ctx)`; por resposta: `message.tokens` (`input output cache_read cache_write thinking reported_cost`) e `message.cost.total` (usa o custo informado pelo OpenRouter quando há `usage.cost`).
- Produz:
  - `AutomatoAgents::Llm::OpenRouterProvider.new(account:)`: `#context -> RubyLLM::Context`, `#chat(model:) -> RubyLLM::Chat`, `#attach(chat)` (= `chat.with_context(context)`), `#fallback_model(id) -> RubyLLM::Model` (`RubyLLM::Model.default(id, 'openrouter')`, porque `with_fallbacks` com string fora do registro quebra). Sem chave → `AutomatoAgents::Llm::MissingApiKeyError` (nunca cai na configuração global).
  - `AutomatoAgents::Usage::Recorder.record!(account:, model:, message:, kind: 'chat', team: nil, conversation: nil) -> UsageEntry` — `cost_source` `reported` se `tokens.reported_cost` presente; `estimated` se só há custo calculado; `unknown` se nenhum.

- [ ] Testes (WebMock em `https://openrouter.ai/api/v1/chat/completions`): chamada usa a chave da variável de ambiente e o modelo pedido (corpo da requisição); resposta com `usage.cost` → entrada `reported` com o valor exato; sem `usage.cost` e modelo fora do registro → `unknown` com custo nulo; sem variável → `MissingApiKeyError`; a configuração global `RubyLLM.config.openrouter_api_key` permanece inalterada após o uso.
- [ ] RED → implementar → GREEN → commit.

### Fatia 0.5 — Agente "eco" de ponta a ponta + rastro + falha

**Arquivos:**
- Migrations: `CreateAutomatoAgentsRuns` — `account_id`, `team_id`, `conversation_id` (FKs cascade), `status` (string not null: `running`|`succeeded`|`failed`), `trigger_message_id` (bigint), `started_at`, `finished_at`, `error_class`, `error_message` (text), `cost_usd` (decimal 14,8), timestamps; índice `[conversation_id, created_at]`. `CreateAutomatoAgentsSteps` — `run_id` (FK cascade), `position` (int not null), `kind` (string not null: `llm_call`|`tool_call`|`handoff`|`message_sent`|`guardrail`|`budget`|`error`), `name` (string), `input` (jsonb default {}), `output` (jsonb default {}), `cost_usd`, `duration_ms` (int), `created_at`; índice `[run_id, position]` único. `AddRunIdToAutomatoAgentsUsageEntries` (nullable, FK nullify).
- Criar: `automato_agents/app/models/automato_agents/run.rb`, `.../step.rb`, `automato_agents/app/services/automato_agents/chatwoot/replier.rb`, `automato_agents/app/services/automato_agents/agents/echo_builder.rb`; substituir o corpo de `Turn#perform`.
- Testes: `spec/automato_agents/services/turn_spec.rb` (integração), `spec/automato_agents/services/chatwoot/replier_spec.rb`.

**Interfaces:**
- Consome: `Agents::Agent.new(name:, instructions:, model:, provider: :openrouter, assume_model_exists: true)`, `Agents::Runner.with_agents(agent)` → `#on_chat_created { |chat, *| provider.attach(chat) }` (ai-agents monta o chat com a configuração global; este gancho troca para o contexto da conta — verificar no teste que a requisição sai com a chave da conta), `#on_llm_call_complete { |agent_name, model, response, _ctx| … }`, `#run(input) -> RunResult(output, messages, usage, error, context)`; `Messages::MessageBuilder.new(agent_bot, conversation, ActionController::Parameters.new(...)).perform` (o bot como `user` vira o remetente; **usar `ActionController::Parameters`**, pois com Hash simples os `items` de `input_select` se perdem); `conversation.bot_handoff!`.
- Produz:
  - `Turn#perform`: cria `Run` (`running`); monta a entrada com as mensagens `incoming` não privadas posteriores à última `outgoing` da conversa (texto unido por quebra de linha); constrói o agente eco (`EchoBuilder.build(setting) -> Agents::Agent`, instruções pt-BR fixas: responder em uma frase curta, confirmando o que o cliente disse); executa; grava `Step` `llm_call` por chamada (custo via `Usage::Recorder`, com `run_id`) e `message_sent`; envia a resposta; finaliza `succeeded` com `cost_usd` somado.
  - Em qualquer erro (incluindo `MissingApiKeyError`, `RunResult#error`, HTTP 5xx): `Step` `error`, `Run` `failed` com classe e mensagem, envia `AccountSetting#fallback_message` e chama `conversation.bot_handoff!`.
  - `Chatwoot::Replier.send_text(conversation:, agent_bot:, content:) -> Message`; `Chatwoot::Replier.send_options(conversation:, agent_bot:, content:, options: [{title:, value:}]) -> Message` (`input_select`).

- [ ] Testes: fluxo feliz com OpenRouter simulado (WebMock) — mensagem incoming → jobs executados → mensagem outgoing do AgentBot com o texto simulado, `Run` `succeeded`, passos `llm_call` + `message_sent`, `UsageEntry` com `run_id`; rajada de 2 incoming → uma resposta só, com as 2 no corpo enviado ao modelo; OpenRouter 500 → mensagem padrão enviada, conversa `open`, `ai_assignee` nulo, `Run` `failed`; sem chave → mesmo caminho de falha; `send_options` grava `content_attributes['items']`; a própria resposta do bot não agenda novo turno.
- [ ] RED → implementar → GREEN → commit.

### Fatia 0.6 — Humano escreve → agente pausa; devolver ao agente

**Arquivos:**
- Migration: `CreateAutomatoAgentsConversationStates` — `conversation_id` (FK cascade, índice único), `account_id`, `team_id` (FKs cascade), `status` (string not null default `'active'`: `active`|`paused`), `paused_at`, `paused_by_id` (bigint, usuário), timestamps.
- Criar: `automato_agents/app/models/automato_agents/conversation_state.rb`, `automato_agents/app/services/automato_agents/conversations/pause_service.rb`, `.../resume_service.rb`; ajustar `EventListener`.
- Testes: `spec/automato_agents/services/conversations/pause_resume_spec.rb`, casos novos no spec do listener.

**Interfaces:**
- Consome: `Message#human_response?` (outgoing, não encaminhada, sem automação/campanha, remetente `User` ou eco externo) + `!message.private?`; `Conversations::AssignmentService` com `assignee_type: 'AgentBot'` (define `ai_assignee` e `pending`).
- Produz:
  - `EventListener#message_created`: se `human_response? && !private?` numa conversa de inbox com equipe → `PauseService.new(conversation:, user: message.sender).perform` (estado `paused`; se `pending`, `conversation.bot_handoff!`). Idempotente.
  - `ResumeService.new(conversation:, user:).perform`: estado `active`; conversa volta a `pending` com `ai_assignee` = bot da equipe (via `AssignmentService`). Erro se a inbox não tem equipe ativa.
  - `ConversationState.for(conversation) -> ConversationState` (find_or_create).

- [ ] Teste de sequência: agente ativo → atendente responde (não privada) → estado `paused`, conversa `open`, sem `ai_assignee` → cliente escreve → nenhum turno → `ResumeService` → `pending` com bot → cliente escreve → turno agendado. Nota privada do atendente não pausa. Resposta do próprio bot não pausa.
- [ ] RED → implementar → GREEN → commit.

### Fatia 0.7 — Orçamento mensal com 3 políticas

**Arquivos:**
- Migration: `AddBudgetToAutomatoAgentsAccountSettings` — `monthly_budget_brl` (decimal 12,2, nullable = sem limite), `usd_brl_rate` (decimal 10,4, not null, default 5.5), `budget_policy` (string, not null, default `'handoff'`: `handoff`|`cheaper_model`|`alert_only`), `cheaper_model` (string, not null, default `'google/gemini-2.5-flash-lite'`), `budget_exceeded_message` (text, not null, default `'No momento vou te passar para alguém da nossa equipe, que já vai te responder.'`).
- Criar: `automato_agents/app/services/automato_agents/budget.rb`; ajustar `Turn`.
- Testes: `spec/automato_agents/services/budget_spec.rb`, casos novos em `turn_spec.rb`.

**Interfaces:**
- Produz: `AutomatoAgents::Budget.new(account).status -> :ok | :exceeded` (soma de `UsageEntry#cost_usd` do mês corrente no fuso `America/Sao_Paulo` × `usd_brl_rate` ≥ `monthly_budget_brl` ⇒ `:exceeded`; sem orçamento ⇒ `:ok`); `#spent_brl -> BigDecimal`.
- `Turn#perform` antes de chamar a IA: `:exceeded` + `handoff` → `Step` `budget`, envia `budget_exceeded_message`, `bot_handoff!`, **nenhuma chamada de IA**; `cheaper_model` → usa `cheaper_model` e registra `Step` `budget`; `alert_only` → segue normal, registra `Step` `budget` e `Rails.logger.warn`.

- [ ] Testes: mês anterior não conta; virada do mês em São Paulo (UTC 02:59 do dia 1 ainda é mês anterior); cada política com o comportamento acima (com WebMock provando que `handoff` não faz requisição e `cheaper_model` envia o modelo econômico); sem orçamento nunca bloqueia.
- [ ] RED → implementar → GREEN → commit.

### Fatia 0.8 — Super Admin: ligar conta e montar equipe

**Arquivos:**
- Criar: `app/dashboards/automato_agents/account_setting_dashboard.rb`, `app/dashboards/automato_agents/team_dashboard.rb` (Administrate, padrão de `app/dashboards/agent_bot_dashboard.rb`), `app/controllers/super_admin/automato_agents/account_settings_controller.rb`, `.../teams_controller.rb` (padrão de `app/controllers/super_admin/agent_bots_controller.rb`; após criar/atualizar equipe chama `Teams::ProvisionService`).
- Modificar: `config/routes.rb` (bloco `super_admin`: `namespace :automato_agents { resources :account_settings, :teams }`), item de navegação do Super Admin (verificar onde o menu é definido e seguir o padrão), `ops/upstream-sync/ours-paths.txt`.
- Testes: `spec/controllers/super_admin/automato_agents/account_settings_controller_spec.rb`, `.../teams_controller_spec.rb` (padrão dos specs existentes de `super_admin`).

**Interfaces:**
- Produz: Super Admin consegue criar/editar `AccountSetting` (conta, ligado, modelo padrão, mensagens, orçamento, política, câmbio) e `Team` (conta, nome, ligado, inboxes da conta — o formulário só aceita inboxes da conta escolhida).

- [ ] Testes: não-super-admin é barrado; criar equipe com 2 inboxes provisiona o AgentBot e os vínculos; inbox de outra conta é rejeitada; desligar a equipe faz o listener ignorar novas mensagens.
- [ ] RED → implementar → GREEN → commit.

### Fatia 0.9 — Produção (fim da fase)

Executada pelo controlador, depois da revisão ampla da fase e com aviso ao usuário:
- [ ] Gerar imagem (`Fork - imagem CE`) e atualizar `chatwoot-rails` e `chatwoot-sidekiq` para a tag nova.
- [ ] Criar serviço `sites/chatwoot-agents` (mesma imagem e env; comando `bundle exec sidekiq -q automato_agents -c 3`; mesmo bind de `/app/storage`; limite de memória). Adicionar `AUTOMATO_AGENTS_OPENROUTER_API_KEY` nos 3 serviços (valor fornecido pelo usuário). Medir RAM; se não couber, rodar a fila no `chatwoot-sidekiq` (`-q automato_agents` adicional) e registrar.
- [ ] Conta laboratório + número de teste (fornecidos pelo usuário) → ligar pelo Super Admin → mandar mensagem → resposta eco; testar pausa/devolução e falha (chave inválida temporária em conta de teste não é possível sem afetar as outras; validar a falha só nos testes automatizados).
- [ ] Atualizar `docs/fork/deploy-easypanel.md` (novo serviço, variável, como ligar).
