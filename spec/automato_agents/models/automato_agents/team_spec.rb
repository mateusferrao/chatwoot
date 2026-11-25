require 'rails_helper'

RSpec.describe AutomatoAgents::Team do
  let(:account) { create(:account) }
  let(:team) { create(:automato_agents_team, account: account) }

  describe 'defaults and validations' do
    it 'is disabled by default' do
      expect(described_class.new.enabled).to be(false)
    end

    it 'requires a name unique within the account' do
      create(:automato_agents_team, account: account, name: 'Vendas')

      expect(build(:automato_agents_team, account: account, name: 'Vendas')).not_to be_valid
      expect(build(:automato_agents_team, account: create(:account), name: 'Vendas')).to be_valid
      expect(build(:automato_agents_team, account: account, name: '')).not_to be_valid
    end

    it 'is invalid when an inbox belongs to another account' do
      team.inboxes.build(account: create(:account), name: 'Outra', channel: create(:channel_widget))

      expect(team).not_to be_valid
      expect(team.errors[:inboxes]).to be_present
    end

    it 'is valid with inboxes of the same account' do
      team.inboxes << create(:inbox, account: account)

      expect(team).to be_valid
    end
  end

  describe 'team inboxes' do
    it 'does not allow an inbox in two teams' do
      inbox = create(:inbox, account: account)
      create(:automato_agents_team_inbox, team: team, inbox: inbox)
      other_team = create(:automato_agents_team, account: account)

      expect(build(:automato_agents_team_inbox, team: other_team, inbox: inbox)).not_to be_valid
      expect { other_team.team_inboxes.new(inbox: inbox).save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'removes the links when the team is destroyed' do
      create(:automato_agents_team_inbox, team: team, inbox: create(:inbox, account: account))

      expect { team.destroy! }.to change(AutomatoAgents::TeamInbox, :count).by(-1)
    end

    it 'nullifies agent_bot_id when the agent bot is deleted' do
      bot = create(:agent_bot, account: account)
      team.update!(agent_bot: bot)

      bot.destroy!

      expect(team.reload.agent_bot_id).to be_nil
    end
  end

  describe 'syncing the agent bot links' do
    let(:inbox) { create(:inbox, account: account) }

    before do
      create(:automato_agents_team_inbox, team: team, inbox: inbox)
      AutomatoAgents::Teams::ProvisionService.new(team).perform
    end

    it 'activates the link when the team is enabled and the account is enabled' do
      create(:automato_agents_account_setting, account: account, enabled: true)
      expect(AgentBotInbox.find_by(inbox_id: inbox.id)).to be_inactive

      team.update!(enabled: true)

      expect(AgentBotInbox.find_by(inbox_id: inbox.id)).to be_active
    end

    it 'deactivates the link when the team is disabled' do
      create(:automato_agents_account_setting, account: account, enabled: true)
      team.update!(enabled: true)

      team.update!(enabled: false)

      expect(AgentBotInbox.find_by(inbox_id: inbox.id)).to be_inactive
    end

    it 'does not re-provision when other attributes change' do
      allow(AutomatoAgents::Teams::ProvisionService).to receive(:new).and_call_original

      team.update!(name: 'Outro nome')

      expect(AutomatoAgents::Teams::ProvisionService).not_to have_received(:new)
    end

    it 'removes the links but keeps the agent bot when the team is destroyed' do
      bot_id = team.reload.agent_bot_id

      team.destroy!

      expect(AgentBotInbox.where(agent_bot_id: bot_id)).to be_empty
      expect(AgentBot.exists?(bot_id)).to be(true)
    end
  end

  describe 'conflicts with the inbox bot' do
    let(:inbox) { create(:inbox, account: account) }

    before do
      create(:automato_agents_team_inbox, team: team, inbox: inbox)
      create(:automato_agents_account_setting, account: account, enabled: true)
      # read again, as the forms do: the team was created with its inboxes loaded empty
      team.reload
    end

    it 'is not enabled while an inbox is linked to another bot, leaving that link alone' do
      other_bot = create(:agent_bot, account: account)
      # enabling the account linked the inbox to the team bot as inactive; another bot takes it over
      inbox.agent_bot_inbox.update!(agent_bot: other_bot)

      expect(team.update(enabled: true)).to be(false)

      expect(team.errors[:base]).to include("The inbox '#{inbox.name}' is already linked to another bot. " \
                                            'Remove that link before adding the inbox to an agent team.')
      expect(team.reload.enabled).to be(false)
      expect(inbox.reload.agent_bot_inbox.agent_bot_id).to eq(other_bot.id)
    end

    it 'is not enabled while Dialogflow answers an inbox' do
      AutomatoAgents::Teams::ProvisionService.new(team).perform
      create(:integrations_hook, :dialogflow, account: account, inbox: inbox)

      expect(team.update(enabled: true)).to be(false)

      expect(team.errors[:base]).to include("#{inbox.name}: Disconnect Dialogflow before connecting Agent Bot")
      expect(team.reload.enabled).to be(false)
      expect(inbox.reload.agent_bot_inbox).to be_inactive
    end

    it 'is always disabled, even while an inbox is linked to another bot' do
      team.update!(enabled: true)
      other_bot = create(:agent_bot, account: account)
      inbox.reload.agent_bot_inbox.update!(agent_bot: other_bot)

      expect(team.update(enabled: false)).to be(true)
    end

    it 'is not checked while the account is disabled' do
      AutomatoAgents::AccountSetting.for(account).update!(enabled: false)
      inbox.agent_bot_inbox.update!(agent_bot: create(:agent_bot, account: account))

      expect(team.update(enabled: true)).to be(true)
    end
  end

  describe 'destroying the team' do
    let(:inbox) { create(:inbox, account: account) }

    before do
      create(:automato_agents_team_inbox, team: team, inbox: inbox)
      create(:automato_agents_account_setting, account: account, enabled: true)
      team.update!(enabled: true)
    end

    it 'hands the conversations pending on the team bot off to humans' do
      conversation = create(:conversation, account: account, inbox: inbox).reload
      expect(conversation).to have_attributes(status: 'pending', assignee_agent_bot_id: team.reload.agent_bot_id)

      team.destroy!

      expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil, ai_assignee_type: nil)
      expect(conversation.waiting_since).to be_present
    end

    it 'does not touch conversations pending on another bot' do
      other_bot = create(:agent_bot, account: account)
      conversation = create(:conversation, account: account, inbox: inbox).reload
      conversation.update!(ai_assignee: other_bot)

      team.destroy!

      expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: other_bot.id)
    end
  end

  describe '#active?' do
    it 'is true only when the team and the account are enabled' do
      team.update!(enabled: true)
      expect(team).not_to be_active

      create(:automato_agents_account_setting, account: account, enabled: true)
      expect(team.reload).to be_active

      team.update!(enabled: false)
      expect(team).not_to be_active
    end
  end

  describe '.for_inbox' do
    it 'returns the team linked to the inbox, or nil' do
      inbox = create(:inbox, account: account)
      create(:automato_agents_team_inbox, team: team, inbox: inbox)

      expect(described_class.for_inbox(inbox)).to eq(team)
      expect(described_class.for_inbox(create(:inbox, account: account))).to be_nil
    end
  end

  describe '#serves?' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox).reload }

    before do
      create(:automato_agents_team_inbox, team: team, inbox: inbox)
      create(:automato_agents_account_setting, account: account, enabled: true)
      team.update!(enabled: true)
    end

    it 'is true for a pending conversation assigned to the team bot' do
      expect(team.reload.serves?(conversation)).to be(true)
    end

    it 'is false once the conversation is no longer pending' do
      conversation.bot_handoff!

      expect(team.reload.serves?(conversation)).to be(false)
    end

    it 'is false for a conversation assigned to another bot' do
      conversation.update!(ai_assignee: create(:agent_bot, account: account))

      expect(team.reload.serves?(conversation)).to be(false)
    end

    it 'is false while the agent is paused in the conversation' do
      AutomatoAgents::ConversationState.for(conversation).pause!(nil)

      expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: team.reload.agent_bot_id)
      expect(team.serves?(conversation)).to be(false)
    end

    it 'is false when the assignee id matches but is not an AgentBot' do
      conversation.ai_assignee_type = 'Captain::Assistant'

      expect(team.reload.serves?(conversation)).to be(false)
    end

    it 'is false when the team is not active' do
      conversation
      AutomatoAgents::AccountSetting.for(account).update!(enabled: false)
      # disabling hands the conversation off; put it back on the bot so only the account state is checked
      conversation.reload.update!(status: :pending, ai_assignee: team.reload.agent_bot)
      expect(conversation).to have_attributes(status: 'pending', assignee_agent_bot_id: team.agent_bot_id)

      expect(team.reload.serves?(conversation)).to be(false)
    end
  end
end
