class SuperAdmin::AutomatoAgents::TeamsController < SuperAdmin::AutomatoAgents::ApplicationController
  def create
    team = new_resource(resource_params)
    authorize_resource(team)

    if save_and_provision(team) { team.save }
      redirect_to after_resource_created_path(team), notice: translate_with_resource('create.success')
    else
      render :new, locals: { page: Administrate::Page::Form.new(dashboard, team) }, status: :unprocessable_entity
    end
  end

  def update
    team = requested_resource

    if save_and_provision(team) { team.update(resource_params) }
      redirect_to after_resource_updated_path(team), notice: translate_with_resource('update.success'), status: :see_other
    else
      render :edit, locals: { page: Administrate::Page::Form.new(dashboard, team) }, status: :unprocessable_entity
    end
  end

  private

  def scoped_resource
    resource_class.includes(:account, :inboxes)
  end

  # Provisions after every successful save, since adding or removing an inbox does not
  # reprovision by itself. On a persisted team, assigning inbox_ids writes the team inboxes right
  # away, so an inbox of another account or of another team raises there; the update transaction
  # is rolled back and the error goes to the form.
  def save_and_provision(team)
    return false unless yield

    ::AutomatoAgents::Teams::ProvisionService.new(team).perform
    true
  rescue ActiveRecord::RecordInvalid, ::AutomatoAgents::Teams::InboxBotConflictError => e
    provisioning_error_messages(e).each { |message| team.errors.add(:base, message) }
    false
  end
end
