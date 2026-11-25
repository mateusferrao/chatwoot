require 'rails_helper'

RSpec.describe AutomatoAgents::Teams::ProvisionService do
  let(:account) { create(:account) }
  let(:team_record) { create(:automato_agents_team, account: account, name: 'Vendas') }
  let(:team) { team_record.reload }
  let(:inbox) { create(:inbox, account: account) }

  before do
    create(:automato_agents_team_inbox, team: team_record, inbox: inbox)
  end

  describe '#perform' do
    it 'creates the team agent bot without an outgoing url' do
      described_class.new(team).perform

      bot = team.reload.agent_bot
      expect(bot).to have_attributes(account_id: account.id, outgoing_url: be_blank, description: 'Automato Agents')
      expect(bot.bot_config).to eq('automato_agents_team_id' => team.id)
    end

    it 'links every team inbox to the bot as active' do
      other_inbox = create(:inbox, account: account)
      create(:automato_agents_team_inbox, team: team_record, inbox: other_inbox)

      described_class.new(team).perform

      links = [inbox, other_inbox].map { |item| item.reload.agent_bot_inbox }
      expect(links).to all(have_attributes(agent_bot_id: team.agent_bot_id, status: 'active'))
    end

    it 'is idempotent' do
      described_class.new(team).perform

      expect { described_class.new(team.reload).perform }.not_to(change { [AgentBot.count, AgentBotInbox.count] })
    end

    it 'reactivates an inactive link of the team bot' do
      described_class.new(team).perform
      inbox.agent_bot_inbox.inactive!

      described_class.new(team.reload).perform

      expect(inbox.reload.agent_bot_inbox).to be_active
    end

    it 'removes the link of inboxes taken out of the team and keeps the others' do
      other_inbox = create(:inbox, account: account)
      create(:automato_agents_team_inbox, team: team_record, inbox: other_inbox)
      described_class.new(team).perform

      team.team_inboxes.find_by!(inbox: inbox).destroy!
      described_class.new(team.reload).perform

      expect(inbox.reload.agent_bot_inbox).to be_nil
      expect(other_inbox.reload.agent_bot_inbox.agent_bot_id).to eq(team.agent_bot_id)
    end

    it 'does not touch links of other bots' do
      other_bot = create(:agent_bot, account: account)
      unrelated_inbox = create(:inbox, account: account)
      create(:agent_bot_inbox, inbox: unrelated_inbox, agent_bot: other_bot, account: account)

      described_class.new(team).perform

      expect(unrelated_inbox.reload.agent_bot_inbox.agent_bot_id).to eq(other_bot.id)
    end

    it 'propagates the validation error when the inbox has an active Dialogflow hook' do
      create(:integrations_hook, :dialogflow, account: account, inbox: inbox)

      expect { described_class.new(team).perform }.to raise_error(ActiveRecord::RecordInvalid, /Dialogflow/)
      expect(AgentBotInbox.where(inbox_id: inbox.id)).to be_empty
    end

    it 'does not provision inboxes of another account' do
      team_record.inboxes << create(:inbox, account: create(:account))

      expect { described_class.new(team).perform }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'conversation flow on a linked inbox' do
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox) }

    before do
      described_class.new(team).perform
      allow(AgentBots::WebhookJob).to receive(:perform_later)
    end

    it 'creates the conversation as pending assigned to the team bot' do
      conversation = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox)

      expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: team.agent_bot_id)
    end

    it 'makes no HTTP request nor enqueues a bot webhook when a message is created' do
      conversation = create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox)

      perform_enqueued_jobs do
        create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
      end

      expect(AgentBots::WebhookJob).not_to have_received(:perform_later)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end
end
