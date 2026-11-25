require 'rails_helper'

RSpec.describe AutomatoAgents::TeamInbox do
  it 'belongs to a team and an inbox' do
    team_inbox = create(:automato_agents_team_inbox)

    expect(team_inbox.team).to be_a(AutomatoAgents::Team)
    expect(team_inbox.inbox.account_id).to eq(team_inbox.team.account_id)
  end

  it 'is destroyed together with the inbox' do
    team_inbox = create(:automato_agents_team_inbox)

    expect { team_inbox.inbox.destroy! }.to change(described_class, :count).by(-1)
  end
end
