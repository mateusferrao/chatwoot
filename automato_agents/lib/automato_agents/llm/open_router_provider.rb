# Builds RubyLLM chats that talk to OpenRouter with the Automato key, through a per-call
# RubyLLM.context. The global RubyLLM configuration belongs to the core and is never touched.
class AutomatoAgents::Llm::OpenRouterProvider
  API_KEY_ENV = 'AUTOMATO_AGENTS_OPENROUTER_API_KEY'.freeze
  APP_NAME = 'Automato Agents'.freeze
  PROVIDER = :openrouter

  def initialize(account:)
    @account = account
  end

  def context
    api_key = ENV.fetch(API_KEY_ENV, nil)
    raise AutomatoAgents::Llm::MissingApiKeyError if api_key.blank?

    RubyLLM.context do |config|
      config.openrouter_api_key = api_key
      config.openrouter_app_name = APP_NAME
      config.openrouter_app_url = ENV.fetch('FRONTEND_URL', nil)
    end
  end

  def chat(model:)
    context.chat(model: model, provider: PROVIDER, assume_model_exists: true)
  end

  def attach(chat)
    chat.with_context(context)
  end

  def fallback_model(model_id)
    RubyLLM::Model.default(model_id, PROVIDER.to_s)
  end
end
