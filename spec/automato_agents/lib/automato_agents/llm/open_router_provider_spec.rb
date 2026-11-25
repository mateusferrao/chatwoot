require 'rails_helper'

RSpec.describe AutomatoAgents::Llm::OpenRouterProvider do
  subject(:provider) { described_class.new(account: account) }

  let(:account) { create(:account) }
  let(:api_key) { 'test-openrouter-key' }
  let(:model) { 'google/gemini-3.1-flash-lite' }
  let(:completions_url) { 'https://openrouter.ai/api/v1/chat/completions' }
  let(:usage) { { prompt_tokens: 12, completion_tokens: 5, total_tokens: 17, cost: 0.00012345 } }
  let(:response_body) do
    {
      id: 'gen-1', object: 'chat.completion', model: model,
      choices: [{ index: 0, finish_reason: 'stop', message: { role: 'assistant', content: 'Olá!' } }],
      usage: usage
    }
  end

  def stub_completion
    stub_request(:post, completions_url)
      .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#chat' do
    it 'calls OpenRouter with the Automato key and the requested model' do
      stub = stub_completion

      with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key do
        provider.chat(model: model).ask('Oi')
      end

      expect(stub.with(headers: { 'Authorization' => "Bearer #{api_key}" }) { |req| JSON.parse(req.body)['model'] == model })
        .to have_been_requested
    end

    it 'returns a response whose cost is the one reported by OpenRouter' do
      stub_completion

      response = with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key do
        provider.chat(model: model).ask('Oi')
      end

      expect(response.tokens.reported_cost).to eq(0.00012345)
      expect(response.cost.total).to eq(0.00012345)
    end

    it 'leaves the global RubyLLM configuration untouched' do
      stub_completion
      global_key = RubyLLM.config.openrouter_api_key

      with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key do
        provider.chat(model: model).ask('Oi')
      end

      expect(RubyLLM.config.openrouter_api_key).to eq(global_key)
      expect(RubyLLM.config.openrouter_api_key).not_to eq(api_key)
    end

    it 'raises MissingApiKeyError without calling OpenRouter when the key is not set' do
      stub = stub_completion

      with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: nil do
        expect { provider.chat(model: model) }.to raise_error(AutomatoAgents::Llm::MissingApiKeyError)
      end

      expect(stub).not_to have_been_requested
    end

    it 'treats a blank key as missing' do
      with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: '' do
        expect { provider.context }.to raise_error(AutomatoAgents::Llm::MissingApiKeyError)
      end
    end
  end

  describe 'request headers' do
    it 'identifies the app with the frontend url' do
      stub = stub_completion

      with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key, FRONTEND_URL: 'https://crm.example.com' do
        provider.chat(model: model).ask('Oi')
      end

      expect(stub.with(headers: { 'X-OpenRouter-Title' => 'Automato Agents', 'HTTP-Referer' => 'https://crm.example.com' }))
        .to have_been_requested
    end

    it 'falls back to the Automato url when FRONTEND_URL is blank' do
      stub = stub_completion

      with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key, FRONTEND_URL: '' do
        provider.chat(model: model).ask('Oi')
      end

      expect(stub.with(headers: { 'X-OpenRouter-Title' => 'Automato Agents', 'HTTP-Referer' => 'https://automato.pro' }))
        .to have_been_requested
    end
  end

  describe '#context' do
    it 'bounds each request to the turn time budget' do
      config = with_modified_env(AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key) { provider.context.config }

      expect(config).to have_attributes(request_timeout: 40, max_retries: 1, retry_max_interval: 5)
    end

    it 'logs the account without the key when the key is missing' do
      allow(Rails.logger).to receive(:error)

      with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: nil do
        expect { provider.context }.to raise_error(AutomatoAgents::Llm::MissingApiKeyError)
      end

      expect(Rails.logger).to have_received(:error).with(/account=#{account.id}/)
    end
  end

  describe '#fallback_model' do
    it 'builds an OpenRouter model for an id outside the registry without raising' do
      fallback = provider.fallback_model('x/y')

      expect(fallback).to be_a(RubyLLM::Model)
      expect(fallback.provider).to eq('openrouter')
      expect(fallback.id).to eq('x/y')
    end
  end
end
