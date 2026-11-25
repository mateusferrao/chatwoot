FactoryBot.define do
  factory :automato_agents_team_inbox, class: 'AutomatoAgents::TeamInbox' do
    team { association :automato_agents_team }
    inbox { association :inbox, account: team.account }
  end
end
