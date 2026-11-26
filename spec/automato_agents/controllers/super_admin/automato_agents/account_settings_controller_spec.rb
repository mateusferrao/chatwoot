require 'rails_helper'

RSpec.describe 'Super Admin automato agents account settings', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account, name: 'Loja Automato') }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:automato_agents_team, account: account, enabled: true) }

  def create_setting(**attributes)
    post '/super_admin/automato_agents/account_settings', params: { automato_agents_account_setting: attributes }
  end

  def update_setting(setting, **attributes)
    patch "/super_admin/automato_agents/account_settings/#{setting.id}", params: { automato_agents_account_setting: attributes }
  end

  def provisioned_team
    create(:automato_agents_team_inbox, team: team, inbox: inbox)
    AutomatoAgents::Teams::ProvisionService.new(team).perform
  end

  context 'when it is not an authenticated super admin' do
    it 'redirects without changing the settings' do
      get '/super_admin/automato_agents/account_settings'
      expect(response).to have_http_status(:redirect)

      create_setting(account_id: account.id, enabled: '1')
      expect(response).to have_http_status(:redirect)
      expect(AutomatoAgents::AccountSetting.count).to eq(0)
    end
  end

  context 'when it is an authenticated super admin' do
    before do
      sign_in(super_admin, scope: :super_admin)
    end

    it 'lists, shows and edits the settings with the budget fields' do
      setting = create(:automato_agents_account_setting, account: account, monthly_budget_brl: 150)

      get '/super_admin/automato_agents/account_settings'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Loja Automato')

      get "/super_admin/automato_agents/account_settings/#{setting.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('150')

      get "/super_admin/automato_agents/account_settings/#{setting.id}/edit"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Agents module enabled', 'automato_agents_account_setting[budget_policy]',
                                       'automato_agents_account_setting[cheaper_model]')
    end

    it 'shows the budget policies by their translated names' do
      setting = create(:automato_agents_account_setting, account: account, budget_policy: 'cheaper_model')

      get "/super_admin/automato_agents/account_settings/#{setting.id}/edit"
      expect(response.body).to include('<option selected="selected" value="cheaper_model">Answer with the cheaper model</option>',
                                       '<option value="handoff">Hand off to humans</option>',
                                       '<option value="alert_only">Only alert</option>')

      get "/super_admin/automato_agents/account_settings/#{setting.id}"
      expect(response.body).to include('Answer with the cheaper model')

      get '/super_admin/automato_agents/account_settings'
      expect(response.body).to include('Answer with the cheaper model')
    end

    it 'offers on the new form only the accounts without a setting' do
      create(:automato_agents_account_setting, account: create(:account, name: 'Já configurada'))
      account

      get '/super_admin/automato_agents/account_settings/new'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Loja Automato')
      expect(response.body).not_to include('Já configurada')
    end

    it 'creates the setting with every business field and activates the team links' do
      provisioned_team

      create_setting(account_id: account.id, enabled: '1', default_model: 'openai/gpt-5-mini', cheaper_model: 'google/gemini-2.5-flash-lite',
                     fallback_message: 'Já te passo para a equipe.', budget_exceeded_message: 'Vou te passar para a equipe.',
                     monthly_budget_brl: '200.50', usd_brl_rate: '5.4', budget_policy: 'cheaper_model')

      setting = AutomatoAgents::AccountSetting.find_by!(account_id: account.id)
      expect(response).to redirect_to("/super_admin/automato_agents/account_settings/#{setting.id}")
      expect(setting).to have_attributes(enabled: true, default_model: 'openai/gpt-5-mini', fallback_message: 'Já te passo para a equipe.',
                                         budget_exceeded_message: 'Vou te passar para a equipe.', monthly_budget_brl: BigDecimal('200.5'),
                                         usd_brl_rate: BigDecimal('5.4'), budget_policy: 'cheaper_model')
      expect(inbox.reload.agent_bot_inbox).to be_active
    end

    it 'disables the module: team links inactive' do
      provisioned_team
      setting = create(:automato_agents_account_setting, account: account, enabled: true)
      expect(inbox.reload.agent_bot_inbox).to be_active

      update_setting(setting, enabled: '0')

      expect(response).to redirect_to("/super_admin/automato_agents/account_settings/#{setting.id}")
      expect(inbox.reload.agent_bot_inbox).to be_inactive
    end

    it 'disables the module through the form even when a team fails, alerting about it' do
      provisioned_team
      other_team = create(:automato_agents_team, account: account, enabled: true)
      other_inbox = create(:inbox, account: account)
      create(:automato_agents_team_inbox, team: other_team, inbox: other_inbox)
      setting = create(:automato_agents_account_setting, account: account, enabled: true)
      expect([inbox, other_inbox].map { |item| item.reload.agent_bot_inbox }).to all(be_active)
      allow(AutomatoAgents::Teams::ProvisionService).to receive(:new).and_wrap_original do |original, provisioned|
        raise AutomatoAgents::Teams::InboxBotConflictError, inbox if provisioned.id == team.id

        original.call(provisioned)
      end

      update_setting(setting, enabled: '0')

      expect(response).to redirect_to("/super_admin/automato_agents/account_settings/#{setting.id}")
      expect(flash[:error]).to start_with('Saved, but provisioning failed: The inbox &#39;')
      expect(setting.reload.enabled).to be(false)
      expect([inbox, other_inbox].map { |item| item.reload.agent_bot_inbox }).to all(be_inactive)
    end

    it 'shows the blank required fields and an invalid budget as form errors' do
      setting = create(:automato_agents_account_setting, account: account)

      update_setting(setting, default_model: '', cheaper_model: '', fallback_message: '', budget_exceeded_message: '',
                              monthly_budget_brl: '-1', budget_policy: 'block')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(CGI.unescapeHTML(response.body)).to include("Default model can't be blank", "Cheaper model can't be blank",
                                                         "Fallback message can't be blank", "Budget exceeded message can't be blank",
                                                         'Monthly budget (BRL) must be greater than or equal to 0',
                                                         'Budget policy is not included in the list')
      expect(setting.reload.default_model).to eq('google/gemini-3.1-flash-lite')
    end

    it 'shows a team that cannot serve its inbox as a form error instead of enabling the module' do
      create(:automato_agents_team_inbox, team: team, inbox: inbox)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot, account: account), account: account)
      setting = create(:automato_agents_account_setting, account: account)

      update_setting(setting, enabled: '1')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('is already linked to another bot')
      expect(setting.reload.enabled).to be(false)
    end

    it 'does not change the account of a setting nor offer deleting it' do
      setting = create(:automato_agents_account_setting, account: account)

      update_setting(setting, account_id: create(:account).id)
      expect(setting.reload.account_id).to eq(account.id)

      delete "/super_admin/automato_agents/account_settings/#{setting.id}"
      expect(response).to have_http_status(:not_found)
      expect(AutomatoAgents::AccountSetting.exists?(setting.id)).to be(true)
    end
  end
end
