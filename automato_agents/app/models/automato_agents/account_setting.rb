# == Schema Information
#
# Table name: automato_agents_account_settings
#
#  id                      :bigint           not null, primary key
#  budget_exceeded_message :text             default("No momento vou te passar para alguém da nossa equipe, que já vai te responder."), not null
#  budget_policy           :string           default("handoff"), not null
#  cheaper_model           :string           default("google/gemini-2.5-flash-lite"), not null
#  default_model           :string           default("google/gemini-3.1-flash-lite"), not null
#  enabled                 :boolean          default(FALSE), not null
#  fallback_message        :text             default("Desculpe, tive um problema por aqui. Vou te passar para alguém da nossa equipe."), not null
#  monthly_budget_brl      :decimal(12, 2)
#  usd_brl_rate            :decimal(10, 4)   default(5.5), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#
# Indexes
#
#  index_automato_agents_account_settings_on_account_id  (account_id) UNIQUE
#
class AutomatoAgents::AccountSetting < ApplicationRecord
  # What a turn does once the monthly budget is exceeded (see AutomatoAgents::Budget): hand the
  # conversation to humans without calling the AI, answer with the cheaper model, or only alert.
  BUDGET_POLICIES = %w[handoff cheaper_model alert_only].freeze

  belongs_to :account

  validates :account_id, uniqueness: true
  validates :budget_policy, inclusion: { in: BUDGET_POLICIES }
  validates :usd_brl_rate, numericality: { greater_than: 0 }
  # nil: no budget
  validates :monthly_budget_brl, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  after_commit :provision_teams, if: :saved_change_to_enabled?, on: [:create, :update]

  def self.for(account)
    find_or_initialize_by(account_id: account.id)
  end

  private

  def provision_teams
    AutomatoAgents::Team.where(account_id: account_id).find_each do |team|
      AutomatoAgents::Teams::ProvisionService.new(team).perform
    end
  end
end
