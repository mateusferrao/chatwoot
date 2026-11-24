# Canais futuros (planejados, não ativos)

Hoje o fork opera **apenas o WhatsApp oficial** ([`whatsapp.md`](whatsapp.md)). Os canais abaixo estão mapeados para quando forem priorizados. Nenhum exige mudança de código, só configuração.

## Instagram e Facebook Messenger

- **Exige um App Meta PRÓPRIO do Chatwoot.** Diferente do WhatsApp, o webhook de Instagram/Messenger é **único por App**, e o App atual da Automato já entrega esses eventos ao automato-api. Compartilhar o App faria um sistema "roubar" os eventos do outro.
- O App novo precisa de **App Review** da Meta para `instagram_manage_messages`, `pages_messaging` e `pages_manage_metadata`, entre outras. A Review pede um vídeo do fluxo funcionando, então só dá para submeter com o Chatwoot no ar. Leva de dias a semanas.
- Configuração:
  - Super Admin → Integrations (grupos **Facebook** e **Instagram**): `FB_APP_ID`, `FB_APP_SECRET`, `FB_VERIFY_TOKEN`, `IG_VERIFY_TOKEN` (e `INSTAGRAM_APP_ID`/`INSTAGRAM_APP_SECRET` para o login direto do Instagram).
  - Webhooks do App: `https://crm.automato.pro/bot` (Messenger) e `https://crm.automato.pro/webhooks/instagram` (Instagram).
- Referência: https://www.chatwoot.com/hc/user-guide/articles/1677778214-how-to-setup-a-facebook-channel e o guia de Instagram na mesma central.

## Caixa de entrada por e-mail

Duas formas de receber e-mails de clientes como conversas:

1. **IMAP/SMTP por caixa** (mais simples). Cada caixa de e-mail (ex.: suporte@…) é conectada direto na criação da inbox, com Google/Microsoft OAuth ou IMAP genérico. Não exige variável de ambiente.
2. **Encaminhamento + Action Mailbox** (respostas por e-mail voltam para a conversa, a "continuidade"). Exige `MAILER_INBOUND_EMAIL_DOMAIN`, `RAILS_INBOUND_EMAIL_SERVICE` e `RAILS_INBOUND_EMAIL_PASSWORD`.
   - ⚠️ **Amazon SES só recebe e-mails (inbound) em algumas regiões.** Confirme se `sa-east-1` está entre elas; se não estiver, a entrada teria de ser em outra região (ex.: `us-east-1`) via SNS (`ACTION_MAILBOX_SES_SNS_TOPIC`), ou com outro provedor (Mailgun, Postmark, SendGrid).

## Widget de chat no site

- Não exige variável de ambiente: crie a caixa **Website** e cole o script nos sites.
- O "Powered by Chatwoot" já sai com `rails fork:branding:apply` (flag `disable_branding`).
- Defina o idioma do widget como Português na configuração da caixa.
