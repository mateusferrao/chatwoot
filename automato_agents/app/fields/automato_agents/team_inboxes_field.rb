require 'administrate/field/base'

# The inboxes of an agent team, picked with checkboxes. Once the team has an account only that
# account inboxes are offered; a new team lists them grouped by account (Team validations reject
# an inbox of another account).
class AutomatoAgents::TeamInboxesField < Administrate::Field::Base
  def self.permitted_attribute(_attribute, _options = nil)
    { inbox_ids: [] }
  end

  def self.searchable?
    false
  end

  def self.sortable?
    false
  end

  def candidate_inboxes_by_account
    inboxes = resource.account_id.present? ? Inbox.where(account_id: resource.account_id) : Inbox.all
    inboxes.includes(:account).order(:account_id, :name).group_by(&:account)
  end

  def selected_ids
    resource.inbox_ids
  end

  def names
    data.map(&:name).sort
  end
end
