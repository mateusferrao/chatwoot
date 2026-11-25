require 'rails_helper'

RSpec.describe AutomatoAgents::Chatwoot::Replier do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent_bot) { create(:agent_bot, account: account) }

  describe '.send_text' do
    it 'creates an outgoing text message sent by the agent bot' do
      message = described_class.send_text(conversation: conversation, agent_bot: agent_bot, content: 'Olá!')

      expect(message).to be_persisted
      expect(message).to have_attributes(
        conversation_id: conversation.id, message_type: 'outgoing', content_type: 'text',
        content: 'Olá!', sender: agent_bot, private: false
      )
    end
  end

  describe '.send_options' do
    it 'creates an input_select message whose items keep the options' do
      options = [{ title: 'Vendas', value: 'sales' }, { title: 'Suporte', value: 'support' }]

      message = described_class.send_options(conversation: conversation, agent_bot: agent_bot, content: 'Com quem quer falar?', options: options)

      expect(message.reload).to have_attributes(content_type: 'input_select', content: 'Com quem quer falar?', sender: agent_bot)
      expect(message.content_attributes['items']).to eq(
        [{ 'title' => 'Vendas', 'value' => 'sales' }, { 'title' => 'Suporte', 'value' => 'support' }]
      )
    end
  end
end
