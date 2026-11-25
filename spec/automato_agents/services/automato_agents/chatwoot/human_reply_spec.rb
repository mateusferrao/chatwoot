require 'rails_helper'

RSpec.describe AutomatoAgents::Chatwoot::HumanReply do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account) }

  def message(message_type: :outgoing, sender: user, **attributes)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: message_type, sender: sender, **attributes)
  end

  # External echoes and automation, template and activity messages have no sender. The message
  # factory assigns one to every message it builds, so it is removed before saving.
  def without_sender(message_type: :outgoing, **attributes)
    built = build(:message, account: account, inbox: inbox, conversation: conversation, message_type: message_type, **attributes)
    built.sender = nil
    built.save!
    built
  end

  def human_reply_in_sql?(created)
    described_class.of(Message.where(id: created.id)).exists?
  end

  def human_reply_in_core?(created)
    !created.private? && created.send(:human_response?)
  end

  # [kind, message, whether it is a human reply]
  def message_kinds
    team_bot = create(:agent_bot, account: account)
    marker = AutomatoAgents::Chatwoot::ReplyMarker.content_attributes(run_id: 1, answered_through: 1)
    [
      ['agent reply', message, true],
      ['agent reply with blank automation and forward keys',
       message(content_attributes: { automation_rule_id: nil, forwarded_message_id: '' }), true],
      ['external echo from the native app', without_sender(content_attributes: { external_echo: true }), true],
      ['automation message', without_sender(content_attributes: { automation_rule_id: 7 }), false],
      # Messages::MessageBuilder takes automation_rule_id from the API params too
      ['agent API message marked with an automation rule', message(content_attributes: { automation_rule_id: 7 }), false],
      ['campaign message sent as an agent', message(additional_attributes: { campaign_id: 3 }), false],
      ['email forwarded by an agent', message(content_attributes: { forwarded_message_id: 12 }), false],
      ['other AgentBot message', message(sender: create(:agent_bot, account: account)), false],
      ['team bot answer', message(sender: team_bot, content_attributes: marker), false],
      ['private note by an agent', message(private: true), false],
      ['template message', without_sender(message_type: :template), false],
      ['activity message', without_sender(message_type: :activity, content: 'Conversa atribuída'), false],
      ['customer message', message(message_type: :incoming, sender: create(:contact, account: account)), false]
    ]
  end

  it 'selects the same messages as the core Message#human_response?, public only' do
    message_kinds.each do |kind, created, human|
      expect([kind, human_reply_in_sql?(created)]).to eq([kind, human])
      expect([kind, human_reply_in_core?(created)]).to eq([kind, human])
    end
  end

  it 'scopes the given relation' do
    reply = message
    other_conversation_reply = create(:message, account: account, inbox: inbox, message_type: :outgoing, sender: user)

    expect(described_class.of(conversation.messages)).to contain_exactly(reply)
    expect(described_class.of(Message.where(conversation_id: other_conversation_reply.conversation_id))).to contain_exactly(other_conversation_reply)
  end
end
