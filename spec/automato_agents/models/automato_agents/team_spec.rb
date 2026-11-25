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
      team.inboxes << create(:inbox, account: create(:account))

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
end
