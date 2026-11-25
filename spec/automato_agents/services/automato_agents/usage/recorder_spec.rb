require 'rails_helper'

RSpec.describe AutomatoAgents::Usage::Recorder do
  let(:account) { create(:account) }
  let(:team) { create(:automato_agents_team, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:tokens) { RubyLLM::Tokens.new(input: 12, output: 5, cache_read: 3, cache_write: 2, thinking: 1, reported_cost: reported_cost) }
  let(:message) { RubyLLM::Message.new(role: :assistant, content: 'Oi', tokens: tokens, model: model) }
  let(:reported_cost) { nil }
  let(:model) { 'x/unknown-model' }

  def record
    described_class.record!(account: account, model: model, message: message, team: team, conversation: conversation)
  end

  context 'when OpenRouter reported the cost' do
    let(:reported_cost) { 0.00012345 }

    it 'stores the exact cost as reported with the token counts' do
      entry = record

      expect(entry).to be_persisted
      expect(entry).to have_attributes(
        account_id: account.id, team_id: team.id, conversation_id: conversation.id,
        provider: 'openrouter', model: model, kind: 'chat', key_source: 'automato',
        input_tokens: 12, output_tokens: 5, cache_read_tokens: 3, cache_write_tokens: 2, thinking_tokens: 1,
        cost_source: 'reported'
      )
      expect(entry.reload.cost_usd).to eq(BigDecimal('0.00012345'))
    end
  end

  context 'when the cost is not reported and the model is not in the registry' do
    it 'stores an unknown cost as null' do
      entry = record

      expect(entry.cost_source).to eq('unknown')
      expect(entry.cost_usd).to be_nil
      expect(entry.input_tokens).to eq(12)
    end
  end

  context 'when the cost is not reported but the registry has pricing for the model' do
    let(:model) { 'google/gemini-2.5-flash-lite' }

    it 'stores the calculated cost as estimated' do
      registry = JSON.parse(File.read(RubyLLM.config.model_registry_file))
      pricing = registry.find { |entry| entry['id'] == model && entry['provider'] == 'openrouter' }&.dig('pricing', 'text_tokens', 'standard')
      expect(pricing).to be_present, "#{RubyLLM.config.model_registry_file} has no openrouter pricing for #{model}; pick a priced model"

      entry = record

      expect(entry.cost_source).to eq('estimated')
      expect(entry.cost_usd).to be_positive
      expect(entry.cost_usd).to eq(message.cost.total.to_d.round(8))
    end
  end

  it 'links the entry to the agent run' do
    run = AutomatoAgents::Run.create!(account: account, team: team, conversation: conversation, status: 'running')

    entry = described_class.record!(account: account, model: model, message: message, run: run)

    expect(entry.run).to eq(run)
  end

  it 'accepts entries without team and conversation and with another kind' do
    entry = described_class.record!(account: account, model: model, message: message, kind: 'vision')

    expect(entry).to have_attributes(team_id: nil, conversation_id: nil, kind: 'vision')
  end

  it 'rejects unknown scope keys' do
    expect { described_class.record!(account: account, model: model, message: message, inbox: 1) }.to raise_error(ArgumentError)
  end
end
