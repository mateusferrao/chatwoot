require 'rails_helper'

RSpec.describe AutomatoAgents::TurnScheduler do
  let(:conversation) { create(:conversation) }
  let(:token_key) { "AUTOMATO_AGENTS::TURN_TOKEN::#{conversation.id}" }

  after do
    Redis::Alfred.delete(token_key)
  end

  describe '.schedule' do
    it 'stores a random token for the conversation that expires in 600 seconds' do
      described_class.schedule(conversation)

      expect(Redis::Alfred.get(token_key)).to be_present
      expect(Redis::Alfred.ttl(token_key)).to be_within(2).of(600)
    end

    it 'enqueues the turn job on the automato_agents queue 4 seconds later with the stored token' do
      freeze_time do
        described_class.schedule(conversation)

        expect(AutomatoAgents::TurnJob).to have_been_enqueued
          .with(conversation.id, Redis::Alfred.get(token_key))
          .on_queue('automato_agents')
          .at(4.seconds.from_now)
      end
    end

    it 'replaces the token on every call so only the latest job stays current' do
      described_class.schedule(conversation)
      first_token = Redis::Alfred.get(token_key)

      described_class.schedule(conversation)

      expect(Redis::Alfred.get(token_key)).not_to eq(first_token)
      expect(AutomatoAgents::TurnJob).to have_been_enqueued.with(conversation.id, first_token)
      expect(AutomatoAgents::TurnJob).to have_been_enqueued.with(conversation.id, Redis::Alfred.get(token_key))
    end
  end
end
