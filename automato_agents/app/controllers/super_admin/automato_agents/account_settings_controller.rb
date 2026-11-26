# No destroy: the module of an account is turned off with "enabled", which deactivates its teams
# (AccountSetting callback, every team even when one fails).
class SuperAdmin::AutomatoAgents::AccountSettingsController < SuperAdmin::AutomatoAgents::ApplicationController
  def create
    setting = new_resource
    authorize_resource(setting)
    save_and_respond(setting, :new)
  end

  def update
    save_and_respond(requested_resource, :edit)
  end

  private

  def scoped_resource
    resource_class.includes(:account)
  end
end
