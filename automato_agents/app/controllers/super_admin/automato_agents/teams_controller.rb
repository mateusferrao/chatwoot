class SuperAdmin::AutomatoAgents::TeamsController < SuperAdmin::AutomatoAgents::ApplicationController
  def create
    team = new_resource
    authorize_resource(team)
    save_and_provision(team, :new)
  end

  def update
    save_and_provision(requested_resource, :edit)
  end

  private

  def scoped_resource
    resource_class.includes(:account, :inboxes)
  end

  # Provisions after every save, since adding or removing an inbox does not reprovision by itself.
  def save_and_provision(team, form)
    save_and_respond(team, form) do
      ::AutomatoAgents::Teams::ProvisionService.new(team).perform
    end
  end
end
