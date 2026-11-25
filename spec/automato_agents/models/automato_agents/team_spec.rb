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

    it 'is false when the assignee id matches but is not an AgentBot' do
      conversation.ai_assignee_type = 'Captain::Assistant'

      expect(team.reload.serves?(conversation)).to be(false)
    end

    it 'is false when the team is not active' do
      conversation
      AutomatoAgents::AccountSetting.for(account).update_columns(enabled: false) # rubocop:disable Rails/SkipsModelValidations -- keeps the conversation pending

      expect(team.reload.serves?(conversation)).to be(false)
    end
  end
end
