require 'rails_helper'

RSpec.describe AutomatoAgents::AccountSetting do
  let(:account) { create(:account) }

  describe '.for' do
    it 'returns an unsaved, disabled record with the defaults when none exists' do
      setting = described_class.for(account)

      expect(setting).to be_new_record
      expect(setting.account_id).to eq(account.id)
      expect(setting.enabled).to be(false)
      expect(setting.default_model).to eq('google/gemini-3.1-flash-lite')
      expect(setting.fallback_message).to eq('Desculpe, tive um problema por aqui. Vou te passar para alguém da nossa equipe.')
    end

    it 'has no budget and the budget defaults' do
      setting = described_class.for(account)

      expect(setting).to have_attributes(
        monthly_budget_brl: nil,
        usd_brl_rate: BigDecimal('5.5'),
        budget_policy: 'handoff',
        cheaper_model: 'google/gemini-2.5-flash-lite',
        budget_exceeded_message: 'No momento vou te passar para alguém da nossa equipe, que já vai te responder.'
      )
    end

    it 'returns the existing record when present' do
      existing = create(:automato_agents_account_setting, account: account, enabled: true)

      expect(described_class.for(account)).to eq(existing)
    end
  end

  describe 'uniqueness' do
    it 'rejects a second setting for the same account in validation' do
      create(:automato_agents_account_setting, account: account)

      duplicate = build(:automato_agents_account_setting, account: account)

      expect(duplicate).not_to be_valid
    end

    it 'rejects a second setting for the same account in the database' do
      create(:automato_agents_account_setting, account: account)

      duplicate = build(:automato_agents_account_setting, account: account)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'budget validations' do
    let(:setting) { build(:automato_agents_account_setting, account: account) }

    it 'accepts each budget policy' do
      %w[handoff cheaper_model alert_only].each do |policy|
        setting.budget_policy = policy

        expect(setting).to be_valid
      end
    end

    it 'rejects an unknown budget policy' do
      setting.budget_policy = 'block'

      expect(setting).not_to be_valid
      expect(setting.errors[:budget_policy]).to be_present
    end

    it 'requires a positive dollar rate' do
      [0, -1, nil].each do |rate|
        setting.usd_brl_rate = rate

        expect(setting).not_to be_valid
        expect(setting.errors[:usd_brl_rate]).to be_present
      end
    end

    it 'accepts no budget, a zero budget and a positive budget' do
      [nil, 0, 150.5].each do |amount|
        setting.monthly_budget_brl = amount

        expect(setting).to be_valid
      end
    end

    it 'rejects a negative budget' do
      setting.monthly_budget_brl = -0.01

      expect(setting).not_to be_valid
      expect(setting.errors[:monthly_budget_brl]).to be_present
    end
  end

  describe 'account deletion' do
    it 'removes the setting when the account is destroyed' do
      create(:automato_agents_account_setting, account: account)

      expect { account.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe 'AutomatoAgents.enabled_for?' do
    it 'is false without a setting' do
      expect(AutomatoAgents.enabled_for?(account)).to be(false)
    end

    it 'is false when disabled' do
      create(:automato_agents_account_setting, account: account, enabled: false)

      expect(AutomatoAgents.enabled_for?(account)).to be(false)
    end

    it 'is true when enabled' do
      create(:automato_agents_account_setting, account: account, enabled: true)

      expect(AutomatoAgents.enabled_for?(account)).to be(true)
    end
  end

  describe 'syncing teams' do
    let(:team) { create(:automato_agents_team, account: account, enabled: true) }
    let(:inbox) { create(:inbox, account: account) }

    before do
      create(:automato_agents_team_inbox, team: team, inbox: inbox)
    end

    it 'activates the team links when the account is enabled and deactivates them when disabled' do
      setting = create(:automato_agents_account_setting, account: account, enabled: true)
      expect(AgentBotInbox.find_by(inbox_id: inbox.id)).to be_active

      setting.update!(enabled: false)

      expect(AgentBotInbox.find_by(inbox_id: inbox.id)).to be_inactive
    end
  end
end
