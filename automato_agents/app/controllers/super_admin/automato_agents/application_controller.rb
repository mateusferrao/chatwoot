# Super Admin screens of the AI agents layer. Its views (custom Administrate fields) live in
# automato_agents/app/views, which only these controllers look up.
class SuperAdmin::AutomatoAgents::ApplicationController < SuperAdmin::ApplicationController
  prepend_view_path Rails.root.join('automato_agents/app/views')

  private

  # Saves in a transaction of its own, so the commit callbacks (provisioning when enabled
  # changes) run once the save is final, then runs the block (more provisioning). Validations
  # catch the conflicts first. A failure before saving (assigning inbox_ids writes the team
  # inboxes right away) is shown on the form; one in provisioning, with the record already
  # saved, redirects to it with an alert.
  def save_and_respond(resource, form)
    saved = false
    ActiveRecord::Base.transaction do
      resource.assign_attributes(resource_params)
      saved = resource.save
      raise ActiveRecord::Rollback unless saved
    end
    return render_form(resource, form) unless saved

    yield if block_given?
    redirect_to [namespace, resource], notice: translate_with_resource(form == :new ? 'create.success' : 'update.success'), status: :see_other
  rescue ActiveRecord::RecordInvalid, ::AutomatoAgents::Teams::InboxBotConflictError => e
    respond_to_failure(resource, form, saved, provisioning_error_messages(e))
  end

  def respond_to_failure(resource, form, saved, messages)
    if saved
      # the Super Admin renders flashes as HTML; inbox names come from account users
      alert = t('automato_agents.super_admin.provisioning_failed', errors: ERB::Util.html_escape(messages.to_sentence))
      redirect_to [namespace, resource], flash: { error: alert }, status: :see_other
    else
      messages.each { |message| resource.errors.add(:base, message) }
      render_form(resource, form)
    end
  end

  def render_form(resource, form)
    render form, locals: { page: Administrate::Page::Form.new(dashboard, resource) }, status: :unprocessable_entity
  end

  def provisioning_error_messages(error)
    case error
    when ::AutomatoAgents::Teams::InboxBotConflictError
      [I18n.t('automato_agents.errors.inbox_linked_to_another_bot', inbox: error.inbox.name)]
    else
      error.record.errors.full_messages
    end
  end
end
