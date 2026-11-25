require 'rails_helper'

RSpec.describe AutomatoAgents::TurnJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:automato_agents_team, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: create(:contact_inbox, inbox: inbox)).reload }
  let(:token_key) { "AUTOMATO_AGENTS::TURN_TOKEN::#{conversation.id}" }
  let(:lock_key) { "AUTOMATO_AGENTS::TURN_LOCK::#{conversation.id}" }
  let(:turn) { instance_double(AutomatoAgents::Turn, perform: nil) }

  before do
    create(:automato_agents_team_inbox, team: team, inbox: inbox)
    create(:automato_agents_account_setting, account: account, enabled: true)
    team.update!(enabled: true)
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

  it 'performs the turn when the token is current and consumes the token' do
    described_class.perform_now(conversation.id, 'current-token')

    expect(AutomatoAgents::Turn).to have_received(:new).with(conversation)
    expect(turn).to have_received(:perform).once
    expect(Redis::Alfred.get(token_key)).to be_nil
  end

  it 'does not repeat the turn when the same job runs again after success' do
    2.times { described_class.perform_now(conversation.id, 'current-token') }

    expect(turn).to have_received(:perform).once
  end

  it 'keeps the token when the turn raises so a retry can run it' do
    allow(turn).to receive(:perform).and_raise(StandardError, 'boom')

    expect { described_class.perform_now(conversation.id, 'current-token') }.to raise_error(StandardError, 'boom')
    expect(Redis::Alfred.get(token_key)).to eq('current-token')
    expect(Redis::Alfred.exists?(lock_key)).to be(false)
  end

  it 'holds the conversation lock for 180 seconds during the turn and releases it afterwards' do
    lock_ttl = nil
    allow(turn).to receive(:perform) { lock_ttl = Redis::Alfred.ttl(lock_key) }

    described_class.perform_now(conversation.id, 'current-token')

    expect(lock_ttl).to be_within(2).of(180)
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

  it 'skips the turn when a human took over after the turn was scheduled' do
    conversation.bot_handoff!

    described_class.perform_now(conversation.id, 'current-token')

    expect(turn).not_to have_received(:perform)
    expect(described_class).not_to have_been_enqueued
    expect(Redis::Alfred.exists?(lock_key)).to be(false)
  end

  it 'skips the turn when the team was disabled after the turn was scheduled' do
    team.update_columns(enabled: false) # rubocop:disable Rails/SkipsModelValidations -- keeps the conversation pending on the bot

    described_class.perform_now(conversation.id, 'current-token')

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

  it 'never runs two turns of the same conversation at the same time, nor repeats it' do
    allow(turn).to receive(:perform) do
      # a duplicate of this job arrives while this turn holds the lock
      described_class.perform_now(conversation.id, 'current-token')
    end

    described_class.perform_now(conversation.id, 'current-token')
    expect(described_class).to have_been_enqueued.with(conversation.id, 'current-token').exactly(:once)

    perform_enqueued_jobs(only: described_class)

    expect(turn).to have_received(:perform).once
  end

  it 'runs a new message turn after the current one, keeping its newer token' do
    newer_token = nil
    allow(turn).to receive(:perform) do
      next if newer_token

      # a new message arrives during the turn and its job hits the busy lock
      AutomatoAgents::TurnScheduler.schedule(conversation)
      newer_token = Redis::Alfred.get(token_key)
      described_class.perform_now(conversation.id, newer_token)
    end

    described_class.perform_now(conversation.id, 'current-token')

    expect(turn).to have_received(:perform).once
    expect(Redis::Alfred.get(token_key)).to eq(newer_token)
    expect(described_class).to have_been_enqueued.with(conversation.id, newer_token).exactly(:twice)

    perform_enqueued_jobs(only: described_class)

    expect(turn).to have_received(:perform).twice
    expect(Redis::Alfred.get(token_key)).to be_nil
  end

  it 'logs the turn' do
    allow(AutomatoAgents::Turn).to receive(:new).and_call_original
    allow(Rails.logger).to receive(:info)

    described_class.perform_now(conversation.id, 'current-token')

    expect(Rails.logger).to have_received(:info).with("[AutomatoAgents] turno conversation=#{conversation.id}")
  end
end
