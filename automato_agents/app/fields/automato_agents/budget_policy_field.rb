require 'administrate/field/select'

# The budget policy of an account setting, shown by its translated name (the Super Admin select
# shows stored values titleized).
class AutomatoAgents::BudgetPolicyField < Administrate::Field::Select
  def selectable_options
    AutomatoAgents::AccountSetting::BUDGET_POLICIES.map { |policy| [label_for(policy), policy] }
  end

  def label
    label_for(data)
  end

  private

  def label_for(policy)
    I18n.t("automato_agents.budget_policies.#{policy}")
  end
end
