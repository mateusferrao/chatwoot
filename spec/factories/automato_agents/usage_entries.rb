FactoryBot.define do
  factory :automato_agents_usage_entry, class: 'AutomatoAgents::UsageEntry' do
    account
    provider { 'openrouter' }
    model { 'google/gemini-3.1-flash-lite' }
    kind { 'chat' }
    cost_source { 'unknown' }
  end
end
