require 'rails_helper'

RSpec.describe AutomatoAgents::TurnJob do
  let(:conversation) { create(:conversation) }
  let(:token_key) { "AUTOMATO_AGENTS::TURN_TOKEN::#{conversation.id}" }
  let(:lock_key) { "AUTOMATO_AGENTS::TURN_LOCK::#{conversation.id}" }
  let(:turn) { instance_double(AutomatoAgents::Turn, perform: nil) }

  before do
    Redis::Alfred.setex(token_key, 'current-token', 600)
    allow(AutomatoAgents::Turn).to receive(:new).and_return(turn)
  end

  after do
    Redis::Alfred.delete(token_key)
    Redis::Alfred.delete(lock_key)
  end

  it 'is enqueued on the automato_agents queue' do
    expect { described_class.perform_later(conversation.id, 'current-token') }
      .to have_enqueued_job(described_class).on_queue('automato_agents')
  end

  it 'performs the turn when the token is still the current one' do
    described_class.perform_now(conversation.id, 'current-token')

    expect(AutomatoAgents::Turn).to have_received(:new).with(conversation)
    expect(turn).to have_received(:perform).once
  end

  it 'holds the conversation lock for 180 seconds during the turn and releases it afterwards' do
    lock_ttl = nil
    allow(turn).to receive(:perform) { lock_ttl = Redis::Alfred.ttl(lock_key) }

    described_class.perform_now(conversation.id, 'current-token')

    expect(lock_ttl).to be_within(2).of(180)
    expect(Redis::Alfred.exists?(lock_key)).to be(false)
  end

  it 'releases the lock when the turn raises' do
    allow(turn).to receive(:perform).and_raise(StandardError, 'boom')

    expect { described_class.perform_now(conversation.id, 'current-token') }.to raise_error(StandardError, 'boom')
    expect(Redis::Alfred.exists?(lock_key)).to be(false)
  end

  it 'discards the job when a newer message replaced the token' do
    Redis::Alfred.setex(token_key, 'newer-token', 600)

    described_class.perform_now(conversation.id, 'current-token')

    expect(turn).not_to have_received(:perform)
    expect(described_class).not_to have_been_enqueued
  end

  it 'discards the job when the token expired' do
    Redis::Alfred.delete(token_key)

    described_class.perform_now(conversation.id, 'current-token')

    expect(turn).not_to have_received(:perform)
  end

  it 'discards the job when the conversation was deleted' do
    conversation_id = conversation.id
    conversation.destroy!

    expect { described_class.perform_now(conversation_id, 'current-token') }.not_to raise_error
    expect(turn).not_to have_received(:perform)
  end

  it 're-enqueues itself with the same token in 5 seconds when the lock is taken' do
    Redis::LockManager.new.lock(lock_key, 180)

    freeze_time do
      described_class.perform_now(conversation.id, 'current-token')

      expect(described_class).to have_been_enqueued
        .with(conversation.id, 'current-token')
        .on_queue('automato_agents')
        .at(5.seconds.from_now)
    end
    expect(turn).not_to have_received(:perform)
  end

  it 'never runs two turns of the same conversation at the same time' do
    allow(turn).to receive(:perform) do
      # a second job of the same conversation arrives while this turn holds the lock
      described_class.perform_now(conversation.id, 'current-token')
    end

    described_class.perform_now(conversation.id, 'current-token')

    expect(turn).to have_received(:perform).once
    expect(described_class).to have_been_enqueued.with(conversation.id, 'current-token').exactly(:once)
  end

  it 'logs the turn' do
    allow(AutomatoAgents::Turn).to receive(:new).and_call_original
    allow(Rails.logger).to receive(:info)

    described_class.perform_now(conversation.id, 'current-token')

    expect(Rails.logger).to have_received(:info).with("[AutomatoAgents] turno conversation=#{conversation.id}")
  end
end
