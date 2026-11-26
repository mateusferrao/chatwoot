require 'administrate/base_dashboard'

class AutomatoAgents::AccountSettingDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    # one setting per account: the new form offers only the accounts without one
    account: Field::BelongsTo.with_options(
      searchable: true,
      searchable_fields: [:name],
      order: 'id DESC',
      scope: -> { Account.where.not(id: AutomatoAgents::AccountSetting.select(:account_id)) }
    ),
    enabled: Field::Boolean,
    default_model: Field::String,
    cheaper_model: Field::String,
    fallback_message: Field::Text,
    budget_exceeded_message: Field::Text,
    # decimals typed as text, the input the Super Admin styles (blank budget: no budget)
    monthly_budget_brl: Field::String.with_options(searchable: false),
    usd_brl_rate: Field::String.with_options(searchable: false),
    budget_policy: AutomatoAgents::BudgetPolicyField,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    enabled
    default_model
    monthly_budget_brl
    budget_policy
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    enabled
    default_model
    cheaper_model
    fallback_message
    monthly_budget_brl
    usd_brl_rate
    budget_policy
    budget_exceeded_message
    created_at
    updated_at
  ].freeze

  BUSINESS_ATTRIBUTES = %i[
    enabled
    default_model
    cheaper_model
    fallback_message
    monthly_budget_brl
    usd_brl_rate
    budget_policy
    budget_exceeded_message
  ].freeze

  # the account of a setting does not change
  FORM_ATTRIBUTES_NEW = [:account, *BUSINESS_ATTRIBUTES].freeze
  FORM_ATTRIBUTES_EDIT = BUSINESS_ATTRIBUTES
  FORM_ATTRIBUTES = FORM_ATTRIBUTES_NEW

  COLLECTION_FILTERS = {}.freeze

  def display_resource(setting)
    setting.account.name
  end
end
