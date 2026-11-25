require 'rails_helper'

RSpec.describe AutomatoAgents::Chatwoot::ReplyMarker do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent_bot) { create(:agent_bot, account: account) }

  def send_marked(sender, answered_through)
    AutomatoAgents::Chatwoot::Replier.send_text(
      conversation: conversation, agent_bot: sender, content: 'Resposta',
      content_attributes: described_class.content_attributes(run_id: 1, answered_through: answered_through)
    )
  end

  describe '.content_attributes' do
    it 'builds the marker under the automato_agents key' do
      expect(described_class.content_attributes(run_id: 3, answered_through: 9))
        .to eq('automato_agents' => { 'run_id' => 3, 'answered_through' => 9 })
    end
  end

  describe '.last_answered_message_id' do
    it 'is nil when the bot sent no marked message' do
      AutomatoAgents::Chatwoot::Replier.send_text(conversation: conversation, agent_bot: agent_bot, content: 'Sem marca')

      expect(described_class.last_answered_message_id(conversation, agent_bot.id)).to be_nil
    end

    it 'is the highest message answered by the given bot in the conversation' do
      send_marked(agent_bot, 15)
      send_marked(agent_bot, 40)
      AutomatoAgents::Chatwoot::Replier.send_text(conversation: conversation, agent_bot: agent_bot, content: 'Sem marca')
      send_marked(create(:agent_bot, account: account), 99)
      other_conversation = create(:conversation, account: account, inbox: inbox)
      AutomatoAgents::Chatwoot::Replier.send_text(
        conversation: other_conversation, agent_bot: agent_bot, content: 'Outra conversa',
        content_attributes: described_class.content_attributes(run_id: 2, answered_through: 120)
      )

      expect(described_class.last_answered_message_id(conversation, agent_bot.id)).to eq(40)
    end
  end
end
