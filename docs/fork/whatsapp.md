# WhatsApp oficial (Cloud API da Meta)

O suporte à API oficial do WhatsApp está no **núcleo MIT** do Chatwoot e funciona integralmente na edição CE. Só as **ligações de voz** pelo WhatsApp são Enterprise (ver [`edicao-ce.md`](edicao-ce.md)).

Este fork habilita os **dois** jeitos de conectar um número:

| Modo | Quando usar | O que precisa |
|---|---|---|
| **Setup manual** | Números da própria operação, ou de clientes que já têm WABA e token | WABA ID, Phone Number ID e token permanente de System User (+ App Secret, recomendado) |
| **Embedded Signup** | Conectar números de clientes com o botão "Conectar com Facebook" | App Meta com Embedded Signup + 3 chaves no Super Admin + feature flag na conta |

## Pré-requisitos (fase 2, depois do deploy)

1. O Chatwoot precisa estar no ar em **HTTPS público** (`https://crm.automato.pro`). A Meta só entrega webhooks em HTTPS válido.
2. `FRONTEND_URL=https://crm.automato.pro` correto: é ele que monta a URL de webhook de cada número.

## App Meta: reaproveitar o App existente

O App Meta da Automato (o mesmo usado pelo automato-api) **pode ser compartilhado com o Chatwoot**:

- O Chatwoot registra o webhook **por número** (`override_callback_uri` na assinatura `subscribed_apps` da WABA). Cada número aponta para `https://crm.automato.pro/webhooks/whatsapp/<numero>` sem mexer no webhook padrão do App, que continua indo para o automato-api.
- Por isso **não é preciso nova App Review**, desde que o App já tenha acesso avançado às permissões `whatsapp_business_management` e `whatsapp_business_messaging`.

> ⚠️ **Um número não pode estar em dois sistemas ao mesmo tempo.** O webhook de um número aponta para um único lugar. Se um número for conectado no Chatwoot, ele deixa de entregar mensagens ao automato-api (e vice-versa). Números na **Evolution API** (não oficial) também precisam ser migrados: ao registrar na Cloud API, a sessão da Evolution para de funcionar.

## Modo 1: setup manual

1. **Meta Business Suite → Configurações do negócio → Usuários do sistema**:
   - Crie (ou reutilize) um usuário do sistema **Admin**.
   - Atribua a ele o App e a WABA (controle total).
   - Gere um **token sem expiração** com as permissões `whatsapp_business_management` e `whatsapp_business_messaging`.
2. **WhatsApp Manager**: anote o **WABA ID** (ID da conta do WhatsApp Business) e o **Phone Number ID** do número.
3. No Chatwoot: **Configurações → Caixas de entrada → Adicionar → WhatsApp → WhatsApp Cloud** e preencha:
   - Nome da caixa
   - WABA ID
   - Phone Number ID
   - Token
   - App Secret: recomendado, para o Chatwoot validar a assinatura dos webhooks
4. O Chatwoot valida as credenciais na Graph API, cria a caixa e **registra o webhook do número automaticamente**. Se o registro falhar, a tela mostra o erro. As causas mais comuns são token sem permissão e App sem acesso à WABA.
5. Teste: mande uma mensagem do seu celular para o número. A conversa deve aparecer no Chatwoot.

## Modo 2: Embedded Signup

1. No **mesmo App Meta**: **WhatsApp → Embedded Signup → Configurations** e crie uma **Configuration nova só para o Chatwoot**. Não reaproveite a do automato-api: assim cada produto controla seus próprios parâmetros. Anote o **Configuration ID**.
2. Em **Configurações do App → Básico**, adicione `crm.automato.pro` nos **Domínios do App** e nas URIs de redirecionamento OAuth válidas.
3. No Chatwoot, **Super Admin** (`https://crm.automato.pro/super_admin`) → **Integrations → WhatsApp Embedded** (`/super_admin/app_config?config=whatsapp_embedded`), configure:
   - `WHATSAPP_APP_ID`: ID do App Meta
   - `WHATSAPP_APP_SECRET`: App Secret
   - `WHATSAPP_CONFIGURATION_ID`: a Configuration criada no passo 1
   - `WHATSAPP_API_VERSION`: deixe o padrão (`v22.0` na v4.20.1), a menos que haja motivo para mudar
4. Habilite o fluxo na conta: Super Admin → Accounts → (conta) → Features → **WhatsApp Embedded Signup Flow** (`whatsapp_embedded_signup_inbox_creation`).
5. Na criação da caixa de WhatsApp aparece o botão **Conectar com Facebook**. O cliente faz login, escolhe ou cria a WABA e o número, e o Chatwoot cria a caixa e registra o webhook sozinho.
6. **Coexistência:** o fluxo suporta números que continuam usando o app **WhatsApp Business** no celular ao mesmo tempo que a Cloud API, se a conta for elegível na Meta.

## Uso no dia a dia

- **Janela de 24h:** fora de 24h desde a última mensagem do cliente, só é possível enviar **templates aprovados** (HSM). O Chatwoot sincroniza os templates da WABA automaticamente (job `TemplatesSyncJob`).
- Crie os templates em **português (`pt_BR`)** no WhatsApp Manager. Variáveis `{{1}}` são preenchidas na hora do envio.
- **Horário comercial:** configure em cada caixa com fuso **America/Sao_Paulo** (Configurações da caixa → Horário comercial).
- **Disparos (campanhas):** existem no núcleo (campanha one-off com template). Analytics de campanha e retomada por destinatário são Enterprise.
- **Saúde do número:** o Chatwoot verifica a qualidade e o status do número periodicamente e avisa por e-mail se precisar reautorizar.

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| Mensagens recebidas não aparecem | Webhook não registrado: confira o erro na criação da caixa, ou se o número ainda está em outro sistema |
| `401` ou "invalid signature" no log do webhook | App Secret errado ou ausente (Super Admin ou caixa) |
| Não consegue responder | Janela de 24h expirada: use um template |
| Token expirou | Token de usuário comum. Use token de **System User** sem expiração |
