FactoryBot.define do
  factory :automato_agents_team, class: 'AutomatoAgents::Team' do
    account
    sequence(:name) { |n| "Equipe #{n}" }
    enabled { false }
  end
end
