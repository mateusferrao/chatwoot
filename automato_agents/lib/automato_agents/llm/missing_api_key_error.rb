class AutomatoAgents::Llm::MissingApiKeyError < StandardError
  def initialize(message = 'AUTOMATO_AGENTS_OPENROUTER_API_KEY is not set')
    super
  end
end
