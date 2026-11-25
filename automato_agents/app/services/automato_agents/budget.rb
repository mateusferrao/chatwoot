# Monthly AI budget of an account, in BRL: the LLM usage recorded in the current calendar
# month of São Paulo, converted with the account dollar rate. Accounts without a budget are
# never exceeded.
class AutomatoAgents::Budget
  TIME_ZONE = 'America/Sao_Paulo'.freeze

  def initialize(account)
    @account = account
    @setting = AutomatoAgents::AccountSetting.for(account)
  end

  def status
    return :ok if @setting.monthly_budget_brl.nil?

    spent_brl >= @setting.monthly_budget_brl ? :exceeded : :ok
  end

  def spent_brl
    @spent_brl ||= spent_usd * @setting.usd_brl_rate
  end

  private

  # Uses the [account_id, created_at] index of the usage ledger.
  def spent_usd
    AutomatoAgents::UsageEntry.where(account_id: @account.id, created_at: Time.current.in_time_zone(TIME_ZONE).all_month).sum(:cost_usd)
  end
end
