require 'rails_helper'

RSpec.describe AutomatoAgents::Conversations::ResumeService do
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

  def pause_and_assign_human
    AutomatoAgents::Conversations::PauseService.new(conversation: conversation, user: user).perform
    Conversations::AssignmentService.new(conversation: conversation.reload, assignee_id: user.id).perform
    expect(conversation.reload).to have_attributes(status: 'open', assignee_id: user.id, ai_assignee: nil)
  end

  it 'returns a paused conversation to the team agent, pending on its bot' do
    pause_and_assign_human

    described_class.new(conversation: conversation, user: user).perform

    expect(AutomatoAgents::ConversationState.sole).to have_attributes(status: 'active', paused_at: nil, paused_by_id: nil)
    expect(conversation.reload).to have_attributes(status: 'pending', assignee_id: nil, ai_assignee: team.reload.agent_bot)
    expect(team.serves?(conversation)).to be(true)
  end

  it 'returns to the agent a conversation that was never paused' do
    conversation.bot_handoff!

    described_class.new(conversation: conversation, user: user).perform

    expect(AutomatoAgents::ConversationState.sole.status).to eq('active')
    expect(conversation.reload).to have_attributes(status: 'pending', ai_assignee: team.reload.agent_bot)
  end

  describe 'without an active team in the inbox' do
    def expect_no_active_team_error
      expect { described_class.new(conversation: conversation, user: user).perform }
        .to raise_error(
          AutomatoAgents::Conversations::NoActiveTeamError,
          "The inbox '#{inbox.name}' has no active agent team to answer the conversation."
        )
      expect(conversation.reload).to have_attributes(status: 'open', assignee_id: user.id)
      expect(AutomatoAgents::ConversationState.sole.status).to eq('paused')
    end

    it 'raises when the team is disabled' do
      pause_and_assign_human
      team.update!(enabled: false)

      expect_no_active_team_error
    end

    it 'raises when the account has the agents disabled' do
      pause_and_assign_human
      AutomatoAgents::AccountSetting.for(account).update!(enabled: false)

      expect_no_active_team_error
    end

    it 'raises when the inbox is in no team' do
      pause_and_assign_human
      AutomatoAgents::TeamInbox.find_by!(inbox: inbox).destroy!

      expect_no_active_team_error
    end
  end
end
