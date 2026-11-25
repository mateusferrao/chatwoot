require 'rails_helper'

RSpec.describe AutomatoAgents::Conversations::PauseService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:automato_agents_team, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: create(:contact_inbox, inbox: inbox)).reload }
  let(:user) { create(:user, account: account) }

  before do
    create(:automato_agents_team_inbox, team: team, inbox: inbox)
    create(:automato_agents_account_setting, account: account, enabled: true)
    team.update!(enabled: true)
  end

  it 'pauses the agent and hands a pending conversation off to humans' do
    expect(conversation).to have_attributes(status: 'pending', assignee_agent_bot_id: team.reload.agent_bot_id)

    state = described_class.new(conversation: conversation, user: user).perform

    expect(state).to have_attributes(status: 'paused', paused_by_id: user.id, paused_at: be_present, team_id: team.id)
    expect(conversation.reload).to have_attributes(status: 'open', ai_assignee: nil, assignee_agent_bot_id: nil, waiting_since: be_present)
  end

  it 'dispatches the native bot handoff event' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    described_class.new(conversation: conversation, user: user).perform

    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, hash_including(conversation: conversation))
  end

  it 'pauses an open conversation without changing it' do
    conversation.bot_handoff!
    human = create(:user, account: account)
    Conversations::AssignmentService.new(conversation: conversation, assignee_id: human.id).perform

    described_class.new(conversation: conversation, user: user).perform

    expect(AutomatoAgents::ConversationState.paused?(conversation)).to be(true)
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: human.id)
  end

  it 'is idempotent: a second reply keeps the first pause and dispatches no new handoff' do
    first_user = user
    described_class.new(conversation: conversation, user: first_user).perform
    paused_at = AutomatoAgents::ConversationState.sole.paused_at
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    travel 1.minute do
      described_class.new(conversation: conversation.reload, user: create(:user, account: account)).perform
    end

    expect(AutomatoAgents::ConversationState.sole).to have_attributes(status: 'paused', paused_by_id: first_user.id, paused_at: paused_at)
    expect(conversation.reload.status).to eq('open')
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_BOT_HANDOFF, any_args)
  end
end
