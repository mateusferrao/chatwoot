# Builds RubyLLM contexts that talk to OpenRouter with the Automato key. The global RubyLLM
# configuration belongs to the core and is never touched.
class AutomatoAgents::Llm::OpenRouterProvider
  API_KEY_ENV = 'AUTOMATO_AGENTS_OPENROUTER_API_KEY'.freeze
  APP_NAME = 'Automato Agents'.freeze
  DEFAULT_APP_URL = 'https://automato.pro'.freeze
  PROVIDER = :openrouter

  # Turn time budget: TurnJob holds the conversation lock for 180 s and the lock is released
  # without an owner check, so a turn must finish well before it (target: 120 s). One LLM call
  # takes at most REQUEST_TIMEOUT, plus one retry after at most RETRY_MAX_INTERVAL:
  # 40 + 5 + 40 = 85 s. The echo agent makes a single call (Turn::MAX_TURNS), leaving ~35 s
  # for sending the reply.
  REQUEST_TIMEOUT = 40
  MAX_RETRIES = 1
  RETRY_MAX_INTERVAL = 5

  def initialize(account:)
    @account = account
  end

  def context
    api_key = ENV.fetch(API_KEY_ENV, nil)
    if api_key.blank?
      Rails.logger.error("[AutomatoAgents] #{API_KEY_ENV} is not set; account=#{@account.id} cannot call OpenRouter")
      raise AutomatoAgents::Llm::MissingApiKeyError
    end

    RubyLLM.context do |config|
      configure_openrouter(config, api_key)
      configure_time_budget(config)
    end
  end

  def chat(model:)
    context.chat(model: model, provider: PROVIDER, assume_model_exists: true)
  end

  def fallback_model(model_id)
    RubyLLM::Model.default(model_id, PROVIDER.to_s)
  end

  private

  def configure_openrouter(config, api_key)
    config.openrouter_api_key = api_key
    config.openrouter_app_name = APP_NAME
    config.openrouter_app_url = ENV.fetch('FRONTEND_URL', nil).presence || DEFAULT_APP_URL
  end

  def configure_time_budget(config)
    config.request_timeout = REQUEST_TIMEOUT
    config.max_retries = MAX_RETRIES
    config.retry_max_interval = RETRY_MAX_INTERVAL
  end
end
