# The first end-to-end agent: it only confirms, in one short sentence, what the customer said.
class AutomatoAgents::Agents::EchoBuilder
  NAME = 'Eco'.freeze
  INSTRUCTIONS = <<~TEXT.freeze
    Você é um assistente de atendimento da Automato. Responda ao cliente em português do Brasil,
    em uma única frase curta, confirmando o que ele disse. Não faça perguntas nem prometa nada.
  TEXT

  # model: the account default model, or its cheaper model when the budget policy asks for it
  def self.build(model:)
    ::Agents::Agent.new(
      name: NAME,
      instructions: INSTRUCTIONS,
      model: model,
      provider: AutomatoAgents::Llm::OpenRouterProvider::PROVIDER,
      assume_model_exists: true
    )
  end
end
