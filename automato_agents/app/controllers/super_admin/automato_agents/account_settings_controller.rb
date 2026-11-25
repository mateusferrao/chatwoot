# No destroy: the module of an account is turned off with "enabled", which deactivates its teams.
class SuperAdmin::AutomatoAgents::AccountSettingsController < SuperAdmin::AutomatoAgents::ApplicationController
  def create
    setting = new_resource(resource_params)
    authorize_resource(setting)

    if save_reporting_provisioning_errors(setting) { setting.save }
      redirect_to after_resource_created_path(setting), notice: translate_with_resource('create.success')
    else
      render :new, locals: { page: Administrate::Page::Form.new(dashboard, setting) }, status: :unprocessable_entity
    end
  end

  def update
    setting = requested_resource

    if save_reporting_provisioning_errors(setting) { setting.update(resource_params) }
      redirect_to after_resource_updated_path(setting), notice: translate_with_resource('update.success'), status: :see_other
    else
      render :edit, locals: { page: Administrate::Page::Form.new(dashboard, setting) }, status: :unprocessable_entity
    end
  end

  private

  def scoped_resource
    resource_class.includes(:account)
  end

  # Turning the module on or off provisions the account teams after the save commits
  # (AccountSetting callback), every team even when one fails.
  def save_reporting_provisioning_errors(setting)
    yield
  rescue ActiveRecord::RecordInvalid, ::AutomatoAgents::Teams::InboxBotConflictError => e
    provisioning_error_messages(e).each { |message| setting.errors.add(:base, message) }
    false
  end
end
