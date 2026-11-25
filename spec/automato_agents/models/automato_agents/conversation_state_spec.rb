require 'rails_helper'

RSpec.describe AutomatoAgents::ConversationState do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:automato_agents_team, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account) }

  before do
    create(:automato_agents_team_inbox, team: team, inbox: inbox)
  end

  describe '.for' do
    it 'creates an active state of the conversation with the inbox team' do
      state = described_class.for(conversation)

      expect(state).to be_persisted
      expect(state).to have_attributes(
        conversation_id: conversation.id, account_id: account.id, team_id: team.id,
        status: 'active', paused_at: nil, paused_by_id: nil
      )
    end

    it 'returns the existing state of the conversation' do
      existing = described_class.for(conversation)

      expect(described_class.for(conversation)).to eq(existing)
      expect(described_class.count).to eq(1)
    end

    it 'returns the state created by a concurrent caller instead of failing on the unique index' do
      existing = create(:automato_agents_conversation_state, conversation: conversation, team: team)
      allow(described_class).to receive(:find_by).and_return(nil)

      expect(described_class.for(conversation)).to eq(existing)
      expect(described_class.count).to eq(1)
    end
  end

  describe '#pause! and #activate!' do
    let(:state) { described_class.for(conversation) }

    it 'records who paused the agent and when, and clears it when the agent is back' do
      freeze_time do
        state.pause!(user)

        expect(state.reload).to have_attributes(status: 'paused', paused_at: Time.current, paused_by_id: user.id)
        expect(described_class.paused?(conversation)).to be(true)
      end

      state.activate!

      expect(state.reload).to have_attributes(status: 'active', paused_at: nil, paused_by_id: nil)
      expect(described_class.paused?(conversation)).to be(false)
    end

    it 'pauses without a user (reply sent from the native app)' do
      state.pause!(nil)

      expect(state.reload).to have_attributes(status: 'paused', paused_by_id: nil)
    end
  end

  describe '.paused?' do
    it 'is false for a conversation without state' do
      expect(described_class.paused?(conversation)).to be(false)
    end
  end

  it 'only accepts the known statuses' do
    expect(build(:automato_agents_conversation_state, status: 'sleeping')).not_to be_valid
  end

  it 'is removed with the conversation' do
    described_class.for(conversation)

    conversation.destroy!

    expect(described_class.count).to eq(0)
  end
end
