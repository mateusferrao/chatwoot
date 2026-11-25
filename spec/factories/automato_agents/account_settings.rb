FactoryBot.define do
  factory :automato_agents_account_setting, class: 'AutomatoAgents::AccountSetting' do
    account
    enabled { false }
  end
end
