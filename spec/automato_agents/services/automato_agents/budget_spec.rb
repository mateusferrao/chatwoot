require 'rails_helper'

RSpec.describe AutomatoAgents::Budget do
  let(:account) { create(:account) }
  let(:budget) { described_class.new(account) }

  def spend(cost_usd, at:, spender: account)
    create(:automato_agents_usage_entry, account: spender, cost_usd: cost_usd, created_at: at)
  end

  def sao_paulo(time)
    Time.find_zone!('America/Sao_Paulo').parse(time)
  end

  describe '#spent_brl' do
    before do
      create(:automato_agents_account_setting, account: account, usd_brl_rate: 5.25, monthly_budget_brl: 100)
    end

    it 'converts the usage of the account in the current month to BRL' do
      travel_to(sao_paulo('2026-11-20 12:00')) do
        spend(1.5, at: sao_paulo('2026-11-01 00:00'))
        spend(0.25, at: sao_paulo('2026-11-20 11:59'))
        spend(nil, at: sao_paulo('2026-11-10 10:00'))
        spend(9, at: sao_paulo('2026-11-10 10:00'), spender: create(:account))

        expect(budget.spent_brl).to be_a(BigDecimal)
        expect(budget.spent_brl).to eq(BigDecimal('9.1875'))
      end
    end

    it 'does not count previous months' do
      travel_to(sao_paulo('2026-11-02 09:00')) do
        spend(3, at: sao_paulo('2026-10-31 23:59'))
        spend(2, at: sao_paulo('2026-09-15 12:00'))

        expect(budget.spent_brl).to eq(0)
      end
    end

    it 'is zero without usage' do
      expect(budget.spent_brl).to eq(0)
    end

    describe 'turn of the month in São Paulo' do
      # São Paulo is UTC-3, so the month turns at 03:00 UTC
      before { spend(1, at: Time.utc(2026, 12, 1, 2, 59)) }

      it 'still counts the previous month at 02:59 UTC of the 1st' do
        travel_to(Time.utc(2026, 12, 1, 2, 59, 30)) do
          expect(budget.spent_brl).to eq(BigDecimal('5.25'))
        end
      end

      it 'starts the new month at 03:00 UTC of the 1st' do
        travel_to(Time.utc(2026, 12, 1, 3, 0)) do
          spend(2, at: Time.utc(2026, 12, 1, 3, 0))

          expect(budget.spent_brl).to eq(BigDecimal('10.5'))
        end
      end
    end
  end

  describe '#status' do
    around do |example|
      travel_to(sao_paulo('2026-11-20 12:00')) { example.run }
    end

    def configure(**attributes)
      create(:automato_agents_account_setting, account: account, usd_brl_rate: 5, **attributes)
    end

    it 'is ok without a budget, whatever was spent' do
      configure(monthly_budget_brl: nil)
      spend(10_000, at: 1.hour.ago)

      expect(budget.status).to eq(:ok)
    end

    it 'is ok when the account has no setting' do
      spend(10_000, at: 1.hour.ago)

      expect(budget.status).to eq(:ok)
    end

    it 'is ok while the spending is below the budget' do
      configure(monthly_budget_brl: 10)
      spend(1.99, at: 1.hour.ago)

      expect(budget.status).to eq(:ok)
    end

    it 'is exceeded once the spending reaches the budget' do
      configure(monthly_budget_brl: 10)
      spend(2, at: 1.hour.ago)

      expect(budget.status).to eq(:exceeded)
    end

    it 'is exceeded above the budget' do
      configure(monthly_budget_brl: 10)
      spend(3, at: 1.hour.ago)

      expect(budget.status).to eq(:exceeded)
    end

    it 'is ok again in a new month' do
      configure(monthly_budget_brl: 10)
      spend(3, at: sao_paulo('2026-10-31 23:59'))

      expect(budget.status).to eq(:ok)
    end

    it 'is exceeded from the start with a zero budget' do
      configure(monthly_budget_brl: 0)

      expect(budget.status).to eq(:exceeded)
    end
  end
end
