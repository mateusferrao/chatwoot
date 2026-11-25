# Super Admin screens of the AI agents layer. Its views (custom Administrate fields) live in
# automato_agents/app/views, which only these controllers look up.
class SuperAdmin::AutomatoAgents::ApplicationController < SuperAdmin::ApplicationController
  prepend_view_path Rails.root.join('automato_agents/app/views')

  private

  # Provisioning runs after the save commits (model callbacks, or the teams controller for an
  # inbox change). Validations catch the conflicts first; one that shows up in between (another
  # bot linked to an inbox meanwhile) is shown on the form instead of a server error.
  def provisioning_error_messages(error)
    case error
    when ::AutomatoAgents::Teams::InboxBotConflictError
      [I18n.t('automato_agents.errors.inbox_linked_to_another_bot', inbox: error.inbox.name)]
    else
      error.record.errors.full_messages
    end
  end
end
