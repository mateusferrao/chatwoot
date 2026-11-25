FactoryBot.define do
  factory :automato_agents_conversation_state, class: 'AutomatoAgents::ConversationState' do
    conversation
    account { conversation.account }
    team { association :automato_agents_team, account: conversation.account }
    status { 'active' }
  end
end
