require 'rails_helper'

RSpec.describe AutomatoAgents::AsyncDispatcherExtension do
  let(:async_dispatcher) { Rails.configuration.dispatcher.async_dispatcher }

  it 'is prepended to the async dispatcher' do
    expect(AsyncDispatcher.ancestors).to include(described_class)
  end

  it 'adds the event listener and keeps the core listeners' do
    expect(async_dispatcher.listeners).to include(AutomatoAgents::EventListener.instance, WebhookListener.instance)
  end

  it 'has the event listener subscribed exactly once when the application booted' do
    subscribed = async_dispatcher.send(:local_registrations).map(&:listener)

    expect(subscribed.count(AutomatoAgents::EventListener.instance)).to eq(1)
  end

  it 'does not subscribe the event listener to the sync dispatcher' do
    subscribed = Rails.configuration.dispatcher.sync_dispatcher.send(:local_registrations).map(&:listener)

    expect(subscribed).not_to include(AutomatoAgents::EventListener.instance)
  end
end
