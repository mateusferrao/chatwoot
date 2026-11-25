require 'rails_helper'

RSpec.describe 'Super Admin automato agents teams', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp vendas') }
  let(:other_inbox) { create(:inbox, account: account, name: 'WhatsApp suporte') }

  def enable_module
    create(:automato_agents_account_setting, account: account, enabled: true)
  end

  def create_team(**attributes)
    post '/super_admin/automato_agents/teams', params: { automato_agents_team: attributes }
  end

  def update_team(team, **attributes)
    patch "/super_admin/automato_agents/teams/#{team.id}", params: { automato_agents_team: attributes }
  end

  def team_with_inbox(enabled: false)
    team = create(:automato_agents_team, account: account, name: 'Vendas')
    create(:automato_agents_team_inbox, team: team, inbox: inbox)
    team.update!(enabled: enabled)
    AutomatoAgents::Teams::ProvisionService.new(team).perform
  end

  context 'when it is not an authenticated super admin' do
    it 'redirects every action without changing teams' do
      team = create(:automato_agents_team, account: account)

      get '/super_admin/automato_agents/teams'
      expect(response).to have_http_status(:redirect)

      create_team(account_id: account.id, name: 'Vendas')
      expect(response).to have_http_status(:redirect)

      delete "/super_admin/automato_agents/teams/#{team.id}"
      expect(response).to have_http_status(:redirect)
      expect(AutomatoAgents::Team.pluck(:id)).to eq([team.id])
    end

    it 'redirects a signed-in agent too' do
      sign_in(create(:user, account: account, role: :administrator), scope: :user)

      get '/super_admin/automato_agents/teams'

      expect(response).to have_http_status(:redirect)
    end
  end

  context 'when it is an authenticated super admin' do
    before do
      sign_in(super_admin, scope: :super_admin)
    end

    it 'lists and shows the teams with their inboxes' do
      team = team_with_inbox

      get '/super_admin/automato_agents/teams'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Vendas')

      get "/super_admin/automato_agents/teams/#{team.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('WhatsApp vendas')
    end

    it 'offers the inboxes on the new form and only the team account inboxes on the edit form' do
      foreign_inbox = create(:inbox, account: create(:account), name: 'Outra conta')
      team = team_with_inbox

      get '/super_admin/automato_agents/teams/new'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('WhatsApp vendas', 'Outra conta')

      get "/super_admin/automato_agents/teams/#{team.id}/edit"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('WhatsApp vendas')
      expect(response.body).not_to include(foreign_inbox.name)
    end

    describe 'creating a team' do
      it 'provisions the agent bot and inactive links while the module is off' do
        create_team(account_id: account.id, name: 'Vendas', enabled: '1', inbox_ids: ['', inbox.id, other_inbox.id])

        team = AutomatoAgents::Team.find_by!(name: 'Vendas')
        expect(response).to redirect_to("/super_admin/automato_agents/teams/#{team.id}")
        expect(team.agent_bot).to have_attributes(account_id: account.id, bot_config: { 'automato_agents_team_id' => team.id })
        expect([inbox, other_inbox].map { |item| item.reload.agent_bot_inbox })
          .to all(have_attributes(agent_bot_id: team.agent_bot_id, status: 'inactive'))
      end

      it 'provisions active links when the team and the module are on' do
        enable_module

        create_team(account_id: account.id, name: 'Vendas', enabled: '1', inbox_ids: [inbox.id, other_inbox.id])

        team = AutomatoAgents::Team.find_by!(name: 'Vendas')
        expect([inbox, other_inbox].map { |item| item.reload.agent_bot_inbox })
          .to all(have_attributes(agent_bot_id: team.agent_bot_id, status: 'active'))
      end

      it 'rejects an inbox of another account on the form' do
        foreign_inbox = create(:inbox, account: create(:account))

        create_team(account_id: account.id, name: 'Vendas', inbox_ids: [inbox.id, foreign_inbox.id])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('must belong to the same account as the team')
        expect(AutomatoAgents::Team.count).to eq(0)
        expect(AgentBotInbox.count).to eq(0)
      end

      it 'shows an inbox linked to another bot as a form error' do
        enable_module
        other_bot = create(:agent_bot, account: account)
        create(:agent_bot_inbox, inbox: inbox, agent_bot: other_bot, account: account)

        create_team(account_id: account.id, name: 'Vendas', enabled: '1', inbox_ids: [inbox.id])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('is already linked to another bot')
        expect(AutomatoAgents::Team.count).to eq(0)
        expect(inbox.reload.agent_bot_inbox.agent_bot_id).to eq(other_bot.id)
      end

      it 'shows a Dialogflow conflict as a form error' do
        enable_module
        create(:integrations_hook, :dialogflow, account: account, inbox: inbox)

        create_team(account_id: account.id, name: 'Vendas', enabled: '1', inbox_ids: [inbox.id])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Disconnect Dialogflow before connecting Agent Bot')
        expect(AutomatoAgents::Team.count).to eq(0)
        expect(inbox.reload.agent_bot_inbox).to be_nil
      end

      it 'requires a name' do
        create_team(account_id: account.id, name: '')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(AutomatoAgents::Team.count).to eq(0)
      end
    end

    describe 'updating a team' do
      it 'reprovisions when an inbox is added and another removed' do
        team = team_with_inbox

        update_team(team, inbox_ids: ['', other_inbox.id])

        expect(response).to redirect_to("/super_admin/automato_agents/teams/#{team.id}")
        expect(inbox.reload.agent_bot_inbox).to be_nil
        expect(other_inbox.reload.agent_bot_inbox).to have_attributes(agent_bot_id: team.reload.agent_bot_id, status: 'inactive')
      end

      it 'rejects an inbox of another account on the form, keeping the team inboxes' do
        team = team_with_inbox
        foreign_inbox = create(:inbox, account: create(:account))

        update_team(team, inbox_ids: [inbox.id, foreign_inbox.id])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('must belong to the same account as the team')
        expect(team.reload.inbox_ids).to eq([inbox.id])
      end

      it 'rejects an inbox of another team on the form' do
        team = team_with_inbox
        create(:automato_agents_team_inbox, team: create(:automato_agents_team, account: account), inbox: other_inbox)

        update_team(team, inbox_ids: [inbox.id, other_inbox.id])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('is already in another agent team')
        expect(team.reload.inbox_ids).to eq([inbox.id])
      end

      it 'shows an inbox linked to another bot as a form error without changing the active team' do
        enable_module
        team = team_with_inbox(enabled: true)
        other_bot = create(:agent_bot, account: account)
        create(:agent_bot_inbox, inbox: other_inbox, agent_bot: other_bot, account: account)

        update_team(team, inbox_ids: [inbox.id, other_inbox.id])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('is already linked to another bot')
        expect(team.reload.inbox_ids).to eq([inbox.id])
        expect(other_inbox.reload.agent_bot_inbox.agent_bot_id).to eq(other_bot.id)
      end

      it 'does not change the account of the team' do
        team = team_with_inbox

        update_team(team, account_id: create(:account).id, name: 'Vendas 2')

        expect(team.reload).to have_attributes(account_id: account.id, name: 'Vendas 2')
      end

      it 'disables the team: links inactive, pending conversations handed off and new messages ignored' do
        enable_module
        team = team_with_inbox(enabled: true)
        conversation = create(:conversation, account: account, inbox: inbox).reload
        expect(conversation).to have_attributes(status: 'pending', assignee_agent_bot_id: team.agent_bot_id)

        update_team(team, enabled: '0')

        expect(inbox.reload.agent_bot_inbox).to be_inactive
        expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
        perform_enqueued_jobs(only: EventDispatcherJob) do
          create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi')
        end
        expect(AutomatoAgents::TurnJob).not_to have_been_enqueued
        expect(create(:conversation, account: account, inbox: inbox).reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
      end
    end

    describe 'destroying a team' do
      it 'removes the links and hands the pending conversations off to humans' do
        enable_module
        team = team_with_inbox(enabled: true)
        conversation = create(:conversation, account: account, inbox: inbox).reload

        delete "/super_admin/automato_agents/teams/#{team.id}"

        expect(response).to redirect_to('/super_admin/automato_agents/teams')
        expect(AutomatoAgents::Team.exists?(team.id)).to be(false)
        expect(inbox.reload.agent_bot_inbox).to be_nil
        expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
      end
    end
  end
end
