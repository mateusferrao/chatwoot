require 'rails_helper'

RSpec.describe AutomatoAgents::Agents::EchoBuilder do
  it 'builds an OpenRouter agent with the account default model and fixed pt-BR instructions' do
    setting = build(:automato_agents_account_setting, default_model: 'x/model')

    agent = described_class.build(setting)

    expect(agent).to be_a(Agents::Agent)
    expect(agent).to have_attributes(name: 'Eco', model: 'x/model', provider: :openrouter, assume_model_exists: true, tools: [])
    expect(agent.instructions).to include('uma única frase curta', 'confirmando o que ele disse')
  end
end
