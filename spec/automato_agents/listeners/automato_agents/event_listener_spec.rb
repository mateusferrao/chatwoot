require 'rails_helper'

RSpec.describe AutomatoAgents::EventListener do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:automato_agents_team, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox).reload }
  let(:token_key) { "AUTOMATO_AGENTS::TURN_TOKEN::#{conversation.id}" }

  before do
    create(:automato_agents_team_inbox, team: team, inbox: inbox)
    create(:automato_agents_account_setting, account: account, enabled: true)
    team.update!(enabled: true)
  end

  after do
    Redis::Alfred.delete(token_key)
    Redis::Alfred.delete("AUTOMATO_AGENTS::TURN_LOCK::#{conversation.id}")
  end

  # Creates the message and runs the real event pipeline: after_create_commit -> Dispatcher ->
  # EventDispatcherJob -> AsyncDispatcher#publish_event -> listeners. Turn jobs stay enqueued.
  def deliver_message(**attributes)
    target_conversation = conversation
    perform_enqueued_jobs(only: EventDispatcherJob) do
      create(:message, account: account, inbox: inbox, conversation: target_conversation, **attributes)
    end
  end

  def expect_no_turn_scheduled
    expect(AutomatoAgents::TurnJob).not_to have_been_enqueued
    expect(Redis::Alfred.get(token_key)).to be_nil
  end

  it 'starts with an eligible conversation pending on the team bot' do
    expect(conversation).to have_attributes(status: 'pending', assignee_agent_bot_id: team.reload.agent_bot_id)
  end

  it 'schedules a turn on the automato_agents queue for an incoming message' do
    deliver_message(message_type: :incoming, content: 'Oi')

    expect(AutomatoAgents::TurnJob).to have_been_enqueued
      .with(conversation.id, Redis::Alfred.get(token_key))
      .on_queue('automato_agents')
      .exactly(:once)
  end

  it 'runs a single turn for a burst of three incoming messages' do
    turn = instance_double(AutomatoAgents::Turn, perform: nil)
    allow(AutomatoAgents::Turn).to receive(:new).and_return(turn)

    %w[Oi tudo bem?].each { |content| deliver_message(message_type: :incoming, content: content) }
    expect(AutomatoAgents::TurnJob).to have_been_enqueued.exactly(3).times

    perform_enqueued_jobs(only: AutomatoAgents::TurnJob)

    expect(AutomatoAgents::Turn).to have_received(:new).with(conversation).once
    expect(turn).to have_received(:perform).once
  end

  it 'ignores the outgoing message sent by the team bot itself' do
    deliver_message(message_type: :outgoing, sender: team.reload.agent_bot, content: 'Resposta do bot')

    expect_no_turn_scheduled
  end

  it 'ignores private messages' do
    deliver_message(message_type: :incoming, private: true)

    expect_no_turn_scheduled
  end

  it 'ignores messages after a human took over the conversation (open)' do
    conversation.bot_handoff!

    deliver_message(message_type: :incoming)

    expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    expect_no_turn_scheduled
  end

  it 'ignores a message whose event is processed after the conversation was resolved' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    conversation.resolved!

    perform_enqueued_jobs(only: EventDispatcherJob)

    expect(conversation.reload).to have_attributes(status: 'resolved', assignee_agent_bot_id: team.reload.agent_bot_id)
    expect_no_turn_scheduled
  end

  it 'ignores conversations assigned to another bot' do
    conversation.update!(ai_assignee: create(:agent_bot, account: account))

    deliver_message(message_type: :incoming)

    expect_no_turn_scheduled
  end

  it 'ignores inboxes that are no longer in a team' do
    conversation
    AutomatoAgents::TeamInbox.find_by!(inbox: inbox).destroy!

    deliver_message(message_type: :incoming)

    expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: team.reload.agent_bot_id)
    expect_no_turn_scheduled
  end

  it 'ignores conversations of a disabled team' do
    conversation
    team.update!(enabled: false)

    deliver_message(message_type: :incoming)

    expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: team.reload.agent_bot_id)
    expect_no_turn_scheduled
  end

  it 'ignores conversations of a disabled account' do
    conversation
    AutomatoAgents::AccountSetting.for(account).update!(enabled: false)

    deliver_message(message_type: :incoming)

    expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: team.reload.agent_bot_id)
    expect_no_turn_scheduled
  end
end
