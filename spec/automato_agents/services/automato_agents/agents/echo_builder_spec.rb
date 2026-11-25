require 'rails_helper'

RSpec.describe AutomatoAgents::Agents::EchoBuilder do
  it 'builds an OpenRouter agent with the given model and fixed pt-BR instructions' do
    agent = described_class.build(model: 'x/model')

    expect(agent).to be_a(Agents::Agent)
    expect(agent).to have_attributes(name: 'Eco', model: 'x/model', provider: :openrouter, assume_model_exists: true, tools: [])
    expect(agent.instructions).to include('uma única frase curta', 'confirmando o que ele disse')
  end
end
