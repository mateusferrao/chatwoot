require 'administrate/base_dashboard'

class AutomatoAgents::TeamDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo.with_options(searchable: true, searchable_fields: [:name], order: 'id DESC'),
    name: Field::String,
    enabled: Field::Boolean,
    inboxes: AutomatoAgents::TeamInboxesField,
    agent_bot: Field::BelongsTo,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    name
    enabled
    inboxes
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    name
    enabled
    inboxes
    agent_bot
    created_at
    updated_at
  ].freeze

  # the account of a team does not change: its agent bot and inboxes belong to it
  FORM_ATTRIBUTES_NEW = %i[
    account
    name
    enabled
    inboxes
  ].freeze
  FORM_ATTRIBUTES_EDIT = %i[
    name
    enabled
    inboxes
  ].freeze
  FORM_ATTRIBUTES = FORM_ATTRIBUTES_NEW

  COLLECTION_FILTERS = {}.freeze

  def display_resource(team)
    team.name
  end
end
