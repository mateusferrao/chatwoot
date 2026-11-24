# Edição Community (CE): o que temos, o que não temos e o que é permitido

## Por que CE

O repositório do Chatwoot tem duas licenças:

- **Tudo fora de `enterprise/`**: licença **MIT**. Pode usar, modificar e rodar em produção livremente.
- **Pasta `enterprise/`**: licença **proprietária** da Chatwoot Inc. ([`enterprise/LICENSE`](../../enterprise/LICENSE)). Uso em produção exige assinatura paga. Modificações nesse código continuam pertencendo à Chatwoot e só podem ser usadas com assinatura.

Mesmo com `enterprise/` presente, sem licença o próprio Chatwoot coloca a instalação no plano `community` e **desliga ativamente** os recursos premium. Quem faz isso é o job `Internal::ReconcilePlanConfigService`, que está dentro de `enterprise/`. Na prática, rodar "Enterprise sem licença" entrega quase o mesmo que a CE, só que sob uma licença restritiva.

Por isso este fork roda a **CE**. A pasta `enterprise/` fica no git apenas para os merges com o upstream ficarem limpos e é **removida no build** ([`ops/scripts/strip-enterprise.sh`](../../ops/scripts/strip-enterprise.sh)), exatamente como o upstream faz no build oficial `-ce`.

> ⚠️ `DISABLE_ENTERPRISE=true` sozinho **não** gera uma CE: `config/application.rb` carrega `enterprise/app/**`, as views e os initializers de qualquer forma. A CE de verdade é a imagem sem a pasta.

## O que a CE NÃO tem

Baseado em `enterprise/config/premium_features.yml` e no conteúdo de `enterprise/` na v4.20.1. Ao atualizar o upstream, confira se a lista mudou.

| Área | Recurso ausente |
|---|---|
| IA (Captain) | Agente de IA que responde clientes, Copilot para atendentes, base de conhecimento com auto-sync de documentos, ferramentas customizadas, servidores MCP, tarefas, classificador, workflows do Copilot, tradução automática |
| Gestão | SLA, Custom Roles (perfis de permissão customizados), Audit Logs (com IP), capacidade por agente e atribuição avançada, monitores de conversa, atributos obrigatórios na conversa |
| Canais | Chamadas de voz (Twilio Voice e **ligações pelo WhatsApp**) |
| Campanhas | Analytics de campanha e rastreio/retomada por destinatário nos disparos de WhatsApp (o disparo em si continua no núcleo) |
| CRM | Enriquecimento automático de empresas, notas nas avaliações CSAT |
| Segurança | SSO via SAML, verificação de dispositivo |
| Busca | Busca avançada (OpenSearch/Elasticsearch) |

## O que a CE TEM (núcleo MIT)

Caixas de entrada e canais (**WhatsApp Cloud API**, site/widget, e-mail, API, Telegram, Line, SMS, Instagram, Facebook, TikTok), contatos, conversas, etiquetas, times, automações, macros, respostas prontas, relatórios, CSAT, campanhas, central de ajuda, **Agent Bots**, webhooks, integrações (OpenAI, Dialogflow, Slack, Linear, Notion, Shopify, Google Translate, Dyte), atributos customizados, atribuição round-robin e MFA.

## Posso implementar o que falta?

| Caminho | Permitido? |
|---|---|
| Copiar, adaptar ou "destravar" código de `enterprise/` (inclusive forçar o plano para `enterprise`) | **Não.** Viola a licença Enterprise |
| Escrever uma implementação **própria, do zero**, sobre o código MIT | **Sim**, mas o esforço é grande (o Captain sozinho é um produto) |
| Usar integrações e extensões do núcleo MIT | **Sim**, e é o recomendado |

Atalhos legítimos para as lacunas mais importantes:

- **IA no atendimento:**
  - Integração **OpenAI** do núcleo: sugestões de resposta, resumo e melhoria de texto.
  - Um **Agent Bot** apontando para um fluxo no **n8n** (que já existe na operação) com o LLM de preferência.
- **SLA e alertas:** automações do Chatwoot + **webhooks** para o n8n (ex.: alertar quando uma conversa passar X minutos sem resposta).
- **Auditoria:** webhooks de eventos de conversa e mensagem gravados num banco ou planilha via n8n.
- **Marca:** nome, logo e URL editáveis no Super Admin; "Powered by" removido via `rails fork:branding:apply`. Isso é código MIT (flag `disable_branding`), não Enterprise.
