require 'rails_helper'

RSpec.describe AutomatoAgents::Teams::ProvisionService do
  let(:account) { create(:account) }
  let(:team) { create(:automato_agents_team, account: account, name: 'Vendas') }
  let(:inbox) { create(:inbox, account: account) }

  before do
    create(:automato_agents_team_inbox, team: team, inbox: inbox)
  end

  def enable_module
    create(:automato_agents_account_setting, account: account, enabled: true)
    team.update!(enabled: true)
  end

  describe '#perform' do
    it 'creates the team agent bot without an outgoing url' do
      described_class.new(team).perform

      bot = team.reload.agent_bot
      expect(bot).to have_attributes(account_id: account.id, outgoing_url: be_blank, description: 'Automato Agents')
      expect(bot.bot_config).to eq('automato_agents_team_id' => team.id)
    end

    it 'links every team inbox to the bot as active when the team is active' do
      other_inbox = create(:inbox, account: account)
      create(:automato_agents_team_inbox, team: team, inbox: other_inbox)
      enable_module

      described_class.new(team).perform

      links = [inbox, other_inbox].map { |item| item.reload.agent_bot_inbox }
      expect(links).to all(have_attributes(agent_bot_id: team.reload.agent_bot_id, status: 'active'))
    end

    it 'links the inboxes as inactive when the team is not active' do
      described_class.new(team).perform

      expect(inbox.reload.agent_bot_inbox).to have_attributes(agent_bot_id: team.reload.agent_bot_id, status: 'inactive')
    end

    it 'is idempotent' do
      enable_module
      described_class.new(team).perform

      expect { described_class.new(team).perform }.not_to(change { [AgentBot.count, AgentBotInbox.count] })
    end

    it 'removes the link of inboxes taken out of the team and keeps the others' do
      other_inbox = create(:inbox, account: account)
      create(:automato_agents_team_inbox, team: team, inbox: other_inbox)
      described_class.new(team).perform

      team.team_inboxes.find_by!(inbox: inbox).destroy!
      described_class.new(team).perform

      expect(inbox.reload.agent_bot_inbox).to be_nil
      expect(other_inbox.reload.agent_bot_inbox.agent_bot_id).to eq(team.reload.agent_bot_id)
    end

    it 'does not touch links of other bots' do
      other_bot = create(:agent_bot, account: account)
      unrelated_inbox = create(:inbox, account: account)
      create(:agent_bot_inbox, inbox: unrelated_inbox, agent_bot: other_bot, account: account)

      described_class.new(team).perform

      expect(unrelated_inbox.reload.agent_bot_inbox.agent_bot_id).to eq(other_bot.id)
    end

    it 'raises a conflict error instead of taking over an inbox linked to another bot' do
      other_bot = create(:agent_bot, account: account)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: other_bot, account: account)

      expect { described_class.new(team).perform }.to raise_error(AutomatoAgents::Teams::InboxBotConflictError, /outro bot/)
      expect(inbox.reload.agent_bot_inbox.agent_bot_id).to eq(other_bot.id)
    end

    it 'propagates the validation error when an active team meets a Dialogflow hook' do
      create(:integrations_hook, :dialogflow, account: account, inbox: inbox)
      create(:automato_agents_account_setting, account: account, enabled: true)

      expect { team.update!(enabled: true) }.to raise_error(ActiveRecord::RecordInvalid, /Dialogflow/)
      expect(inbox.reload.agent_bot_inbox).to be_inactive
    end

    it 'does not conflict with Dialogflow while the team is not active' do
      create(:integrations_hook, :dialogflow, account: account, inbox: inbox)

      expect { described_class.new(team).perform }.not_to raise_error
      expect(inbox.reload.agent_bot_inbox).to be_inactive
    end
  end

  describe 'conversation flow on a linked inbox' do
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }

    def new_conversation
      create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox).reload
    end

    before do
      described_class.new(team).perform
    end

    it 'leaves the conversation open and unassigned while the module is off' do
      expect(new_conversation).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    end

    it 'creates the conversation as pending assigned to the team bot when team and account are enabled' do
      enable_module

      expect(new_conversation).to have_attributes(status: 'pending', assignee_agent_bot_id: team.reload.agent_bot_id)
    end

    it 'stops taking new conversations when the team is disabled' do
      enable_module
      team.update!(enabled: false)

      expect(new_conversation).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    end

    it 'stops taking new conversations when the account setting is disabled' do
      enable_module
      AutomatoAgents::AccountSetting.for(account).update!(enabled: false)

      expect(new_conversation).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    end

    it 'stops taking new conversations when the team is destroyed, keeping the bot' do
      enable_module
      bot_id = team.reload.agent_bot_id
      team.destroy!

      expect(new_conversation).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
      expect(AgentBot.exists?(bot_id)).to be(true)
    end

    describe 'handoff of conversations the team stops serving' do
      def expect_handed_off(conversation)
        expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil, ai_assignee_type: nil)
        expect(conversation.waiting_since).to be_present
      end

      it 'hands off the pending bot conversations when the team is disabled' do
        enable_module
        conversation = new_conversation

        team.update!(enabled: false)

        expect_handed_off(conversation)
      end

      it 'hands off the pending bot conversations when the account setting is disabled' do
        enable_module
        conversation = new_conversation

        AutomatoAgents::AccountSetting.for(account).update!(enabled: false)

        expect_handed_off(conversation)
      end

      it 'hands off only the conversations of an inbox removed from an active team' do
        enable_module
        kept_inbox = create(:inbox, account: account)
        create(:automato_agents_team_inbox, team: team, inbox: kept_inbox)
        described_class.new(team).perform
        removed_conversation = new_conversation
        kept_conversation = create(:conversation, account: account, inbox: kept_inbox).reload

        team.team_inboxes.find_by!(inbox: inbox).destroy!
        described_class.new(team).perform

        expect_handed_off(removed_conversation)
        expect(kept_conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: team.agent_bot_id)
      end

      it 'does not touch conversations pending on another bot' do
        enable_module
        other_bot = create(:agent_bot, account: account)
        conversation = new_conversation
        conversation.update!(ai_assignee: other_bot)

        team.update!(enabled: false)

        expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: other_bot.id)
      end
    end

    it 'makes no HTTP request nor enqueues a bot webhook when a message is created' do
      enable_module
      conversation = new_conversation
      allow(AgentBots::WebhookJob).to receive(:perform_later).and_call_original

      perform_enqueued_jobs do
        create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
      end

      expect(AgentBots::WebhookJob).not_to have_received(:perform_later)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end
end
