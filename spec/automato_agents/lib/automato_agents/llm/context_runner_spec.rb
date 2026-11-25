require 'rails_helper'

RSpec.describe AutomatoAgents::Llm::ContextRunner do
  let(:completions_url) { 'https://openrouter.ai/api/v1/chat/completions' }
  let(:llm_context) { RubyLLM.context { |config| config.openrouter_api_key = 'context-key' } }
  let(:agent) { Agents::Agent.new(name: 'Eco', instructions: 'Repita.', model: 'x/model', provider: :openrouter, assume_model_exists: true) }
  let(:response_body) do
    {
      id: 'gen-1', object: 'chat.completion', model: 'x/model',
      choices: [{ index: 0, finish_reason: 'stop', message: { role: 'assistant', content: 'Oi!' } }],
      usage: { prompt_tokens: 3, completion_tokens: 2, total_tokens: 5 }
    }
  end
  let!(:completion_stub) do
    stub_request(:post, completions_url)
      .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def run_agent(callbacks: {})
    described_class.new(llm_context).run(agent, 'Oi', registry: { agent.name => agent }, max_turns: 1, callbacks: callbacks)
  end

  describe 'ai-agents contract' do
    let(:upgrade_message) do
      'AutomatoAgents::Llm::ContextRunner overrides the private Agents::Runner#build_chat(agent) and calls ' \
        'Agents::Runner#run directly (ai-agents 0.14.0). Re-check runner.rb before changing the gem version.'
    end

    it 'is pinned to ai-agents 0.14.0' do
      expect(Agents::VERSION).to eq('0.14.0'), upgrade_message
    end

    it 'overrides a private Agents::Runner#build_chat that takes the agent' do
      expect(Agents::Runner.private_method_defined?(:build_chat)).to be(true), upgrade_message
      expect(Agents::Runner.instance_method(:build_chat).parameters).to eq([[:req, :agent]]), upgrade_message
    end

    it 'relies on the Agents::Runner#run signature' do
      expect(Agents::Runner.instance_method(:run).parameters).to eq(
        [[:req, :starting_agent], [:req, :input], [:key, :context], [:key, :registry], [:key, :max_turns],
         [:key, :headers], [:key, :params], [:key, :callbacks]]
      ), upgrade_message
    end
  end

  it 'builds the chat from the given context so the request carries its key' do
    result = run_agent

    expect(result).to be_success
    expect(result.output).to eq('Oi!')
    expect(completion_stub.with(headers: { 'Authorization' => 'Bearer context-key' })).to have_been_requested.once
  end

  it 'uses the context key even when the global configuration has another OpenRouter key' do
    global_key = RubyLLM.config.openrouter_api_key
    RubyLLM.config.openrouter_api_key = 'global-key'

    run_agent

    expect(completion_stub.with(headers: { 'Authorization' => 'Bearer context-key' })).to have_been_requested.once
    expect(a_request(:post, completions_url).with(headers: { 'Authorization' => 'Bearer global-key' })).not_to have_been_made
  ensure
    RubyLLM.config.openrouter_api_key = global_key
  end

  it 'emits llm_call_complete with the model and the response' do
    calls = []

    run_agent(callbacks: { llm_call_complete: [proc { |_agent_name, model, response| calls << [model, response.content] }] })

    expect(calls).to eq([['x/model', 'Oi!']])
  end
end
