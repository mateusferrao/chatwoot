# Design: camada de agentes de IA

> **Status:** aprovado em 25/11/2026. Fonte de verdade da camada de agentes do fork. Mudanças de escopo passam por atualização deste documento.
>
> Execução: fatias testáveis com revisão independente (seção E). Progresso por fatia nos PRs.


## E. Método de execução: fatias testáveis + revisão independente

> "Implementação por fatias testáveis: implementação → revisão → achou erro? Volta para a implementação. Subagentes independentes para revisão."

Segue a skill superpowers:subagent-driven-development, adaptada ao fork.

**Ciclo por fatia:**
1. **Brief da fatia** (arquivo no workspace): objetivo, escopo, arquivos, critérios de aceite e testes obrigatórios. É a única fonte de requisitos para quem implementa.
2. **Implementação:** um subagente implementador *novo*.
   - Trabalha com TDD.
   - Roda RSpec na worktree CE (`ops/scripts/strip-enterprise.sh --confirm`), mais rubocop e eslint dos arquivos tocados.
   - Faz commit e escreve um relatório num arquivo.
   - Nunca dispara outros subagentes.
3. **Revisão independente**, com subagentes *novos*. Eles recebem **só o brief e o diff** (pacote BASE..HEAD), nunca a minha conclusão:
   - **Revisor de especificação e correção**, em toda fatia;
   - **revisor de segurança**, nas fatias sensíveis (credenciais, SSRF, permissões, ferramentas, orçamento, dados de contato);
   - **revisor de frontend**, nas fatias de tela (i18n, `components-next`, Tailwind, a11y).
4. **Achou erro?**
   - Eu verifico cada apontamento: não aceito nem descarto às cegas.
   - Os procedentes voltam ao **mesmo implementador**.
   - Depois vem uma re-revisão focada no diff da correção.
   - O limite é de 5 rodadas. Se estourar, paro e trago para você com as evidências.
5. **Fatia aprovada:**
   - PR (rascunho → pronto) com título em Conventional Commits, em pt-BR;
   - CI verde;
   - merge e deploy conforme a regra de autonomia (abaixo).
6. **Fim de cada fase:** revisão ampla do conjunto, com um revisor novo no modelo mais capaz, antes de ligar a fase em produção.

**Autonomia (decisão do usuário):**
- **Merge automático na `main`** quando a revisão independente estiver limpa e o CI verde. Só paro em:
  - bloqueio;
  - limite de rodadas estourado;
  - ação destrutiva ou de risco;
  - falta de insumo do usuário (ex.: credenciais do Clinicorp, número de teste).
- **Deploy em produção só ao fim de cada fase**, depois da revisão ampla. Aviso o usuário antes.
  - A trilha B não altera o runtime de produção.
  - O deploy da Fase 0 inclui criar o serviço `chatwoot-agents`.

**Controle:**
- Um ledger (`progress.md` no workspace da skill, git-ignored) registra cada fatia: BASE, commits, rodadas de revisão, decisões e PR. Ele sobrevive à compactação de contexto.
- Uma fatia por vez, em sequência, na branch `claude/modest-brahmagupta-8vq993`, que é reiniciada da `main` após cada merge.

**Testes no CI:**
- O `run_foss_spec.yml` só procura specs em `spec/`.
- As specs do módulo ficarão em `spec/automato_agents/`. Assim o CI as roda sem mudar o workflow do upstream.

### Fatias

Cada fatia entrega algo verificável por teste automatizado. Quando indicado, também por verificação em produção.

**Trilha B: blindagem**

| # | Fatia | Prova |
|---|---|---|
| B1 | Workflow `fork-upstream-mirror.yml` + `sync-upstream.sh` aceita o espelho local + runbook `docs/fork/independencia-upstream.md` | Workflow manual verde; script testado com o espelho |
| B2 | Arquivo dos pacotes `@chatwoot/*` e das gems `ai-agents`/`twitty` + `use-vendored-packages.sh` + job manual de build offline | Imagem compila só com os arquivos locais |

**Fase 0: fundação**

| # | Fatia | Prova |
|---|---|---|
| 0.1 | Esqueleto `automato_agents/` (via `eager_load_paths`, sem gem/engine), `account_settings` + interruptor, registro em `ours-paths.txt` | Boot na CE; specs de modelo |
| 0.2 | `teams` + serviço que cria o AgentBot (sem URL) e liga as inboxes | Conversa nova na inbox ligada nasce `pending` com `ai_assignee` = bot |
| 0.3 | Ponte de eventos (prepend no `AsyncDispatcher`), filtros, `TurnJob` na fila `automato_agents`, debounce + lock | Rajada de mensagens → 1 turno; privadas, saídas e equipe desligada são ignoradas |
| 0.4 | Porta de IA (adaptador OpenRouter via `RubyLLM.context`; provedor falso nos testes) + ledger `usage_entries` | Custo gravado por chamada |
| 0.5 | Agente "eco" de ponta a ponta + rastro `runs`/`steps` + falha → mensagem padrão + transferência | Mensagem entra → resposta sai como bot; caminho de falha |
| 0.6 | Humano escreve → pausa; "devolver ao agente" | Sequência pausa → devolve → responde |
| 0.7 | SSRF própria, credenciais criptografadas, orçamento com as 3 políticas | Rede privada bloqueada; estouro por política |
| 0.8 | Produção: serviço `chatwoot-agents` no Easypanel, conta laboratório, medição de RAM | Eco respondendo no número de teste |

**Fase 1: primeiro cliente (clínicas)**

| # | Fatia |
|---|---|
| 1.1 | Documento de configuração + JSON Schema + rascunho/publicar/versões/rollback (API) |
| 1.2 | Permissão por campo (`field_policies`) + políticas Super Admin × Administrador na API |
| 1.3 | Especialistas com `ai-agents` (transferir/consultar, persona visível, limite de passagens, especialista ativo) |
| 1.4 | Fatos confirmados + histórico com resumo |
| 1.5 | Conhecimento: arquivos + FAQ, ingestão (extrair, dividir, embedding), busca pgvector com citação |
| 1.6 | Guardrail "só da base" + conteúdo como dado (anti-injeção) + formato WhatsApp (`input_select`) |
| 1.7 | Ferramentas HTTP (definição, autenticação, timeout, SSRF, credenciais, modo simulado) |
| 1.8 | Ações no Chatwoot (etiquetas, atributos, notas, contato) + transferência para humano por regras e horário |
| 1.9 | Procedimento-formulário (campos tipados, validadores, confirmação) |
| 1.10 | Procedimento em etapas (máquina de estados, ramos, lista, aprovação humana, retomada) |
| 1.11 | Spike Clinicorp (credenciais de teste) → ferramentas e configuração de referência da clínica |
| 1.12 | Entrada de áudio, imagem e PDF (porta Media) |
| 1.13 | Telas de Configurações (equipe, especialistas, conhecimento, ferramentas, regras, orçamento) com campos travados + publicar, versões, diff e rollback |
| 1.14 | Playground (API + tela, ferramentas simuladas) |
| 1.15 | Painel "o que o agente fez" na conversa (+ pausar/devolver) |
| 1.16 | Uso e custo básico (tela) |
| 1.17 | Go-live: conta laboratório → clínica de teste → cliente |

O plano detalhado de cada fase (briefs com arquivos, testes e critérios exatos) sai pela skill superpowers:writing-plans antes de cada fase.

## 0. Pré-requisito: blindagem contra o sumiço do upstream (pedido do usuário)

> "Se o repo pai do fork for apagado, o nosso precisa estar imune."

Será um PR próprio, **antes** da Fase 0 dos agentes. Situação levantada:

| Dependência do upstream | Situação hoje | Medida |
|---|---|---|
| **Repositório Git** | `mateusferrao/chatwoot` **não é um fork no GitHub** (`fork:false`, confirmado via API) e tem o **histórico completo** até a v4.20.1. Se o `chatwoot/chatwoot` for apagado, **nada acontece com o nosso** | Nenhuma no repo. Acrescentar o workflow agendado `fork-upstream-mirror.yml` (semanal + manual), que guarda um **git bundle** do upstream (`develop`, `master` e todas as tags) como asset de uma *Release* do nosso repo (últimas 8 mantidas). Bundle em Release, e não refs empurradas no repo, porque o `GITHUB_TOKEN` não pode empurrar commits que alteram `.github/workflows` e porque branches do upstream no nosso repo poderiam disparar workflows deles. Se o upstream sumir, temos a última cópia; se a cópia falhar, o job fica vermelho e não afeta nada |
| **Pacotes npm da Chatwoot Inc.** | 7 pacotes `@chatwoot/*` no `pnpm-lock.yaml`: captain-avatar, jumpbar, ninja-keys, pico-search, prosemirror-schema, utils, viz. Se forem despublicados, o **build da imagem quebra** | Arquivar os tarballs exatos (versão do lockfile) em `vendor/fork-mirror/npm/`, com a licença de cada um, e criar o script `ops/scripts/use-vendored-packages.sh`. Ele troca para `file:` (via `pnpm.overrides`) só em emergência, para não mexer em `package.json` sem necessidade |
| **Gems da Chatwoot Inc.** | `ai-agents` 0.14.0 (base dos nossos agentes) e `twitty` 0.1.5 | Mesmo arquivamento dos `.gem` em `vendor/fork-mirror/gems/`; o script também cobre o Gemfile (`path:`/`vendor/cache`) |
| **Imagens Docker** | As nossas imagens CE estão no GHCR do nosso repo. As bases são `node`/`ruby` oficiais do Docker Hub, não da Chatwoot | Nunca apagar as imagens publicadas: elas rodam sem nada do upstream. Documentar o rollback por tag |
| **Serviços online da Chatwoot Inc. em produção** | `ChatwootHub` (ping de versão, registro, push relay) tem todas as chamadas com `rescue` (`lib/chatwoot_hub.rb:92-129`). Se o hub sumir, o sistema segue funcionando, mas o **push para os apps móveis oficiais** para (os apps também são da Chatwoot Inc.) | Documentar: atendimento pelo navegador/PWA, que não depende deles. Opcional: `ENABLE_PUSH_RELAY_SERVER=false`. Os links de termos e privacidade em `installation_config` apontam para chatwoot.com; são cosméticos |
| **Atualizações** | `ops/scripts/sync-upstream.sh` busca no `chatwoot/chatwoot` | `sync-upstream.sh` aceita `--source <bundle ou URL>` para atualizar a partir do bundle espelhado; documentado |

**Verificação:**
- Um build da imagem com `use-vendored-packages.sh` ativado e **sem acesso** aos pacotes `@chatwoot/*` e às gems da Chatwoot. É um job manual no workflow da imagem que usa os arquivos locais.
- O job de espelho rodando verde uma vez.

**Documento:** `docs/fork/independencia-upstream.md`, um "runbook" do que fazer se o upstream sumir.

## 1. Intenção

A Automato vende atendimento por IA no WhatsApp para vários clientes, de vários nichos. Cada cliente é uma **conta** em `crm.automato.pro`.

Em cada conta, uma **equipe de agentes especialistas** atende e **resolve sozinha**:
- Ela entende texto, áudio, imagem e PDF.
- Ela responde com a base de conhecimento do cliente.
- Ela age em sistemas externos e no próprio Chatwoot.
- Ela conduz ações críticas com procedimentos garantidos em código.
- Ela passa a conversa para humanos por regras.

A configuração fica dentro do Chatwoot. A Automato monta o agente, e o cliente edita apenas os campos que a Automato liberar.

O primeiro nicho é **clínicas com agendamento**. Há um candidato, sem prazo rígido. O volume esperado em 12 meses é **pequeno**: até ~10 contas e centenas de conversas por dia.

### Objetivos
- Configurar um cliente novo **sem código**, só por configuração.
- Seguir **desacoplado por portas**: provedor de IA, tipo de ferramenta, tipo de conhecimento e canal. Trocar o OpenRouter por outro provedor deve ser trivial.
- Dar rastreabilidade total do que o agente fez, além de observabilidade, monitoramento e guardrails.

### Anti-objetivos (fracasso mesmo que "funcione")
1. **O agente inventar** preço, prazo ou política.
2. **Cada cliente virar código** customizado para coisas comuns.
3. **Custo de IA sem teto ou sem visibilidade** por conta.

### Não-objetivos (por ora)
- Canais além do WhatsApp.
- Rastreador de sites e catálogo estruturado como fonte de conhecimento.
- Editor visual de fluxos.
- Avaliação automática por casos de teste.
- Política de retenção de dados (decidir depois).

## 2. Restrições (fatos do código v4.20.1 CE)

**Edição CE:**
- **Captain (agente nativo) é Enterprise**: indisponível e proibido copiar.
- Nada do MIT usa pgvector. A busca semântica é nossa.
- Papéis de conta são só `administrator` e `agent` (`app/models/account_user.rb:36`). `SuperAdmin < User` (`app/models/super_admin.rb:47`).

**Agent Bot e entrega de eventos:**
- Com `outgoing_url` vazio, o AgentBot **não envia webhook** (`app/listeners/agent_bot_listener.rb:84-85`).
- Mesmo assim, a inbox com AgentBotInbox ativo faz a conversa nascer `pending`, com `ai_assignee` = bot (`conversation.rb:315-333`).
- O `bot_handoff!` (`conversation.rb:185-198`) e os relatórios de handoff funcionam nativamente.
- `AsyncDispatcher#listeners` (`app/dispatchers/async_dispatcher.rb`) é o ponto de entrada de eventos.
- `prepend_mod_with` só carrega `enterprise/` e `custom/`, e o CE não tem extensões. Portanto o encaixe será um `prepend` explícito feito pelo nosso módulo.

**WhatsApp:**
- O único formato interativo é `input_select`: botões (≤3) ou lista.
- A resposta do cliente chega como **texto do título**.
- Fora de 24 h, só template.

**Infra:**
- VPS de 2 vCPU / ~8 GB, compartilhada.
- **Não há staging.**
- O SMTP ainda está pendente (alertas por e-mail dependem dele).

**Dependências já no `Gemfile.lock` (sem dependência nova):**
- **`ruby_llm` 2.1.1** (MIT, ativo): agentes, ferramentas, **cliente MCP nativo** (HTTP/OAuth), transcrição, visão, PDF/OCR, embeddings, rerank, moderação, Judge, avaliações, **ledger de custo**, fallbacks, OpenTelemetry e ~20 provedores, incluindo o OpenRouter.
- **`ai-agents` 0.14.0** (Chatwoot Inc., **MIT**): multiagente com handoff no mesmo turno e "agente como ferramenta".
- `neighbor` e `pgvector`.
- `Redis::LockManager` (`lib/redis/lock_manager.rb`).

**Bibliotecas descartadas** (paradas, violam a regra de dependências):
- `langgraph_rb` (0.1.11, out/2025)
- `langchainrb` (mai/2025)

## 3. Abordagens consideradas

- **A. Módulo dentro do Chatwoot (engine Rails isolada).** ✅ **ESCOLHIDA pelo usuário.**
  - Uma só fonte de dados, login e permissões.
  - Sem o teto de 5 s do webhook e sem as restrições do token de bot.
  - Um sistema só para operar na VPS pequena.
  - Custo: fica em Ruby, e cada sync do upstream pode exigir ajustes.
- **B. Serviço separado (Python/TS) ligado como Agent Bot.**
  - Desacoplamento físico.
  - Custo: dois sistemas, ponte de login/permissão, token de admin para editar contato, fila contra os 5 s e mais RAM.
- **Descartadas:**
  - n8n como motor: o usuário não o escolheu nem para ferramentas.
  - Plataformas de terceiros: contrariam configurabilidade e controle de custo.
- **Modelo de comportamento:**
  - Também se compararam "agentes livres" e "fluxo visual (grafo)".
  - Fechado: **especialistas livres + procedimentos**, com fluxo em etapas **por ação**, executado em código.

## 4. Decisões do usuário

1. Clientes = contas neste Chatwoot.
2. O agente atende e **resolve sozinho**.
3. Capacidades: conhecimento, APIs de sistemas, ações no Chatwoot, mídia/templates e proatividade.
4. Partimos do zero.
5. Configuração **dentro do Chatwoot**, com **permissão por campo**: a Automato decide o que o cliente edita.
6. **Vários especialistas** por conta, com ligações **transferir** (passa o controle) e **consultar** (pergunta e volta).
7. **Fatos confirmados compartilhados** entre especialistas.
8. **Procedimentos:** formulário (campos validados + confirmação) e **fluxo em etapas** (máquina de estados por ação: passos determinísticos ou de IA, ramos, pausa/retomada, aprovação humana, follow-up).
9. Troca de especialista **visível ou não: configurável por agente**.
10. **Memória resumida do contato** entre conversas (configurável por agente).
11. Entrada de **áudio, imagem e PDF**.
12. Conhecimento por **arquivos + FAQ editado na tela**.
13. Ferramentas de três tipos: **HTTP configurável na tela**, **servidores MCP remotos** e **plugins em código** por nicho.
14. **Proativo:** follow-up sem resposta, evento externo (webhook), lembrete combinado na conversa e templates.
15. Transferência para humano configurável: pedido explícito, "não sei"/limites/erros, temas sensíveis/regras, horário/sem humano.
16. **Humano escreve → agente pausa** até "devolver ao agente" ou resolução.
17. IA via **OpenRouter** (padrão, com a chave da Automato e margem). O provedor é trocável. Chave própria do cliente é opcional (Fase 3).
18. Limite de gasto: **comportamento configurável por conta** (humano / modelo mais barato / só alerta).
19. Validação:
    - playground;
    - **versões publicadas + rollback**;
    - revisão de conversas;
    - **na conversa real, mostrar tudo o que o agente fez**;
    - observabilidade, monitoramento e guardrails.
20. Retenção: **guardar tudo por enquanto**.
21. Fases 0 → 1 → 2 → 3, como na seção 9.

## 5. Arquitetura

```
Chatwoot (Rails)                                   automato_agents/ (nosso)
───────────────                                    ─────────────────────────────────────────
WhatsApp → mensagem → AsyncDispatcher ──prepend──► AutomatoAgents::EventListener
                                                      │ (filtra: inbox com equipe ativa, conversa
                                                      │  pending + ai_assignee = nosso AgentBot,
                                                      │  mensagem do cliente não privada)
                                                      ▼
                                   Sidekiq fila "automato_agents" (processo próprio chatwoot-agents)
                                                      │ TurnJob: debounce → lock por conversa
                                                      ▼
   ┌──────────── Runtime ────────────────────────────────────────────────────────────┐
   │ 1. Entrada: transcreve áudio / lê imagem / extrai PDF (porta Media)              │
   │ 2. Contexto: versão publicada + estado da conversa (especialista ativo, fatos,   │
   │    procedimentos) + histórico (mensagens Chatwoot + resumo) + memória do contato │
   │ 3. ai-agents Runner: especialistas compilados da config; ferramentas =           │
   │    conhecimento, HTTP, MCP, plugins, ações Chatwoot, procedimentos, transferir/  │
   │    consultar, humano                                                              │
   │ 4. Guardrails de saída (afirmações só da base, formato WhatsApp, limites)        │
   │ 5. Envia como AgentBot (Messages::MessageBuilder; input_select; anexos)          │
   │ 6. Persiste estado, rastro (runs/steps) e uso/custo; checa orçamento             │
   └──────────────────────────────────────────────────────────────────────────────────┘
Portas (interfaces trocáveis): LlmProvider (ruby_llm/OpenRouter) · ToolKind (http, mcp, plugin, chatwoot,
knowledge, procedure) · KnowledgeSource (arquivo, faq) · Media (áudio, imagem, pdf) · Channel (WhatsApp/Chatwoot)
```

**Encaixe no Chatwoot**, com o mínimo de diff upstream. Cada mudança é registrada em `ops/upstream-sync/ours-paths.txt`.
- **Um AgentBot por equipe**, criado pelo módulo, com `outgoing_url` vazio.
  - Ele é ligado às inboxes da equipe via AgentBotInbox.
  - Com isso aproveitamos nativamente `pending`, `ai_assignee`, `bot_handoff!`, os relatórios e o remetente "bot".
- **Eventos:** um initializer do módulo faz `AsyncDispatcher.prepend(...)` para acrescentar o nosso listener. Nenhum arquivo upstream é editado para isso.
- **Ações no Chatwoot:** usam serviços e modelos internos (`Messages::MessageBuilder`, `Conversations::AssignmentService`, labels, `custom_attributes`, contato).
  - Não passam pela API HTTP, então não esbarram nas restrições do token de bot.
- **Arquivos upstream tocados** (todos registrados):
  - `config/application.rb`: `automato_agents/app/**` e `automato_agents/lib` nos `eager_load_paths`, como o `enterprise/`;
  - `config/routes.rb`: mount;
  - registro de rotas e item no menu de Configurações (`settings.routes.js`, `Sidebar.vue`);
  - registro do painel lateral da conversa;
  - `config/sidekiq.yml`, se a fila precisar ser declarada;
  - `db/schema.rb`: tabelas do módulo (as migrations ficam em `db/migrate`, geradas com `rails g migration`).

> **Decisão (plano da Fase 0):** em vez de engine/gem por path, o código fica no diretório `automato_agents/`, adicionado aos `eager_load_paths`. Gem por path exigiria editar o `Gemfile.lock` (sobrescrito a cada sync) e migrations de engine não entram no `db:chatwoot_prepare`. Ver [`plano-fase-0.md`](plano-fase-0.md).
- **Risco:** `db/schema.rb` vai conflitar a cada sync.
  - `ops/scripts/sync-upstream.sh` deve passar a regenerar o schema: migrar um banco limpo após o merge.

## 6. Modelo de dados (prefixo `automato_agents_`, todas com `account_id`)

| Tabela | Conteúdo |
|---|---|
| `teams` | Equipe de agentes da conta, ligada a 1..n inboxes e ao AgentBot. Guarda `draft` (documento jsonb), `published_version_id`, `enabled` (desliga na hora) e `field_policies` (quais caminhos do documento o cliente pode editar; só Super Admin altera) |
| `versions` | Snapshot imutável do documento publicado (número, autor, data, nota). Base do rollback e do diff |
| `account_settings` | Orçamento por período, política ao estourar, margem, provedor/modelos padrão, chave BYOK criptografada (Fase 3), ligado/desligado |
| `tools` | Ferramentas da conta: `kind` (http/mcp/plugin), definição (endpoint, método, esquema de parâmetros, descrição) e credenciais **criptografadas** (AR encryption já configurada) |
| `knowledge_sources` / `knowledge_chunks` | Arquivo (Active Storage) ou FAQ. Os chunks guardam texto, metadados, `embedding vector(N)` e o modelo de embedding usado |
| `conversation_states` | Uma por conversa: versão usada, especialista ativo, status (ativo/pausado/humano), **fatos confirmados**, **procedimentos em andamento**, resumo do histórico, contadores, `lock_version` |
| `runs` / `steps` | Rastro: cada turno (gatilho, versão, status, erro, latência, custo) e cada passo (chamada de IA, ferramenta com entrada e saída, transferência, guardrail, procedimento) |
| `usage_entries` | Ledger: provedor, modelo, tipo (chat/embedding/transcrição/visão), tokens, custo real, custo cobrado (com margem), origem da chave |
| `contact_memories` (Fase 2) | Resumo e preferências por contato, com origem (conversa) |
| `scheduled_actions` (Fase 2) | Follow-ups, lembretes e esperas de procedimentos |

**Configuração como documento versionado (jsonb validado por JSON Schema):**
- especialistas: persona, instruções, modelo, visibilidade, ligações transferir/consultar, ferramentas permitidas, escopo de conhecimento;
- procedimentos;
- regras de transferência;
- horários;
- guardrails;
- mensagens padrão.

As ferramentas são referenciadas por id. Plugins (Fase 3) registram fragmentos de schema, o que é extensível sem migrations. O runtime **só lê versões publicadas**.

## 7. Comportamento do runtime

**Turno:**
- **Debounce:** espera alguns segundos configuráveis, agrupando rajadas de mensagens do WhatsApp.
- **Lock por conversa** (`Redis::LockManager`): um turno por vez.
- **Limites:** máximo de passos de IA por turno, de passagens entre especialistas por turno (ex.: 3) e de chamadas de ferramenta, com timeout por ferramenta.

**Especialistas:**
- Transferir e consultar são ferramentas geradas a partir das ligações configuradas (`ai-agents` handoff / agent_tool).
- O especialista ativo é salvo na conversa.
- Persona visível ou voz única, conforme a configuração.

**Contexto em quatro camadas:**
1. Histórico compartilhado (com resumo).
2. **Fatos confirmados**, injetados como "não contradizer". Vêm de campos validados e resultados de ferramentas.
3. Procedimentos em andamento.
4. Memória do contato (Fase 2).

Credenciais e ferramentas ficam isoladas por especialista.

**Procedimentos:**
- **Formulário:** campos tipados com validação em código (ex.: CPF com dígito verificador), confirmação explícita do resumo pelo cliente e só então executa a ação.
- **Em etapas (Fase 1):** máquina de estados declarativa por ação. Passos determinísticos (o código chama a ferramenta) ou de IA, ramos por condição, pergunta em lista do WhatsApp, aprovação humana, retomada, espera e follow-up.
- O procedimento pertence à **conversa**: um desvio de assunto não o perde.

**Guardrails:**
- Afirmações de preço, prazo e política **só com trecho da base ou resultado de ferramenta**. Sem isso: "vou confirmar com a equipe" e, opcionalmente, transfere.
- Conteúdo de ferramentas e base é tratado como **dado**, nunca como instrução (proteção contra injeção de prompt).
- Ações com efeito colateral só via procedimento confirmado.
- **Proteção SSRF própria:** bloqueia rede privada em URLs de ferramentas e MCP. Só **MCP remoto**; nunca stdio.
- Limite por contato contra abuso.
- Orçamento por conta.
- Interruptor geral por conta e equipe.

**Humano e pausas:**
- Uma mensagem **humana** (não privada) numa conversa com agente ativo **pausa** o agente.
- A ação "devolver ao agente", no painel, faz o bot reassumir.
- A transferência para humano usa `bot_handoff!` + time/agente configurado + aviso ao cliente, conforme horário.

**Falhas:**
- Erro de IA: fallback de modelo (`ruby_llm` `with_fallbacks`).
- Se persistir: mensagem padrão + transferência para humano.
- Tudo registrado no rastro.

## 8. Telas (dentro do Chatwoot, Vue/Tailwind, componentes `components-next`)

- **Configurações → Agentes de IA** (Administrador da conta + Super Admin membro):
  - equipes, especialistas, procedimentos, conhecimento, ferramentas, regras, horários e orçamento;
  - cada campo **editável ou bloqueado** conforme `field_policies`. Super Admin vê tudo e define as políticas;
  - rascunho → **publicar** (com nota) → histórico de versões, diff e rollback;
  - **playground**: chat de teste contra o rascunho, mostrando passos, ferramentas e trechos usados. Ferramentas com efeito colateral rodam em modo simulado por padrão.
- **Painel na conversa**, "o que o agente fez":
  - especialista ativo, fatos, procedimentos e passos de cada turno, com entrada e saída das ferramentas;
  - botões pausar / devolver ao agente.
  - *Minha decisão:* a visão detalhada é para administradores e Super Admin; atendentes veem o resumo, porque respostas de ferramentas podem ter dados sensíveis.
- **Uso e custo** por conta, equipe e período (Fase 1 básico; Fase 3 com margem e faturamento).
- **i18n:** textos novos em `en.json`/`en.yml` (padrão upstream) **e** `pt_BR` (o fork é em português).

## 9. Fases

| Fase | Entrega | Em produção quando |
|---|---|---|
| **0. Fundação** | Engine, tabelas, listener + fila/processo `chatwoot-agents`, porta de IA (OpenRouter via ruby_llm), ledger de custo, criptografia de credenciais, SSRF, interruptor, regra "humano escreveu → pausa", AgentBot por equipe | Um agente "eco" de teste responde numa conta laboratório |
| **1. Primeiro cliente (clínicas)** | Spike da API Clinicorp (teste), especialistas (transferir/consultar), fatos, conhecimento (arquivos + FAQ, pgvector) + guardrail "só da base", procedimento-formulário **e procedimento em etapas**, ferramentas HTTP, ações Chatwoot, regras de transferência + horário, áudio/imagem/PDF, painel na conversa, telas com permissão por campo, versões/rollback, playground, orçamento configurável | Agente de clínica agendando de ponta a ponta na conta laboratório e depois no cliente |
| **2. Autonomia** | Proativo (follow-up, webhook de evento externo, lembretes, templates), memória resumida, MCP remoto | |
| **3. Escala comercial** | Plugins de nicho em código, BYOK, relatório de custo com margem/faturamento, revisão de conversas, OpenTelemetry e alertas | |

## 10. Verificação

- Specs RSpec do módulo, rodados na worktree CE (`ops/scripts/strip-enterprise.sh --confirm`, como no CI `run_foss_spec.yml`).
- IA simulada nos testes, com respostas gravadas.
- Testes de sequência:
  - debounce/lock;
  - pausa humana → devolver;
  - transferir/consultar;
  - procedimento com CPF inválido → válido → confirmação;
  - guardrail sem fonte;
  - estouro de orçamento por política;
  - SSRF bloqueado.
- **Sem staging** (*minha decisão*): uma **conta laboratório** em produção, com número de teste do WhatsApp. O módulo fica desligado por padrão e é ligado por conta. O playground serve antes de ligar.
- Caso de referência da Fase 1: clínica com FAQ + tabela de preços (arquivo) + agenda via ferramenta HTTP. Cobre agendar, remarcar, dúvida de preço sem fonte e pedido de humano.

## 11. Fica a cargo de quem construir

Nome exato de classes e arquivos, chunking/embedding (modelo e dimensão), tempo de debounce padrão, formato do JSON Schema, estrutura do sync do `db/schema.rb`, detalhes visuais das telas.

## 12. Revisão do design (builder check) e respostas

**Respostas do usuário:**
- **Agenda de referência: Clinicorp** (ambiente de teste); ajustar a cada cliente depois.
  - Com isso, o **procedimento em etapas sobe para a Fase 1**: remarcar e escolher horário vindo da API são multi-etapas.
  - O primeiro passo da Fase 1 é um *spike* da API do Clinicorp: autenticação, horários livres, agendar, remarcar e cancelar. Ele depende de **credenciais de teste** que o usuário fornecerá.
  - O módulo não assume nada da API antes desse spike.
- **LGPD/saúde: nada agora.**
  - Sem restrição ZDR, sem criptografia do rastro, sem aviso ao paciente.
  - Fica registrado como risco consciente do usuário.
  - O design deixa as portas previstas: filtro de provedores na porta de IA e texto de apresentação configurável.
- **Cliente publica sozinho**, dentro dos campos liberados. A Automato vê o histórico e pode reverter.

**Decisões minhas (marcadas para revisão):**
- **Modelos:**
  - Catálogo próprio do módulo, uma lista de modelos permitidos mantida pela Automato. Não usa `config/llm.yml`, para não conflitar com o upstream.
  - Cada especialista escolhe um modelo do catálogo. Se o cliente pode trocá-lo é definido pela `field_policy`.
  - A configuração do `ruby_llm` é por contexto (`RubyLLM.context`), e não global. Assim, BYOK (Fase 3) não exige contorno e não interfere nas chaves `CAPTAIN_OPEN_AI_*` do núcleo.
- **Orçamento:**
  - Custo real = valor informado pelo OpenRouter em cada chamada; sem ele, estimativa pela tabela do `ruby_llm`. Fica gravado em USD no ledger.
  - O limite é definido em **BRL**, com câmbio configurado pela Automato.
  - Período = mês do calendário, fuso America/Sao_Paulo.
  - O "modelo mais barato" da política é definido pela Automato por conta.
- **Permissão por campo** vale para o documento (especialistas, procedimentos, regras, mensagens) e também para ferramentas, credenciais, conhecimento e orçamento.
  - Ferramentas, credenciais e orçamento ficam **só Automato** por padrão.
  - Conhecimento e FAQ ficam **editáveis pelo cliente** por padrão.
- **Processo Sidekiq próprio (`chatwoot-agents`):**
  - Concorrência baixa (ex.: 3) e limite de memória no Easypanel.
  - Se a RAM da VPS não comportar, a fila roda no `chatwoot-sidekiq` atual, com prioridade baixa. A medição acontece na Fase 0.
- **Mínimo para o go-live do 1º cliente:** a Fase 1 inteira, como o usuário aprovou.
