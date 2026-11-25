require 'rails_helper'

RSpec.describe AutomatoAgents::Run do
  let(:account) { create(:account) }
  let(:team) { create(:automato_agents_team, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:run) { described_class.create!(account: account, team: team, conversation: conversation, status: 'running') }

  it 'only accepts the documented statuses' do
    expect(described_class.new(status: 'done')).to be_invalid
    expect(run).to be_valid
  end

  describe '#add_step!' do
    it 'appends steps in position order' do
      run.add_step!(kind: 'llm_call', name: 'x/model')
      run.add_step!(kind: 'message_sent')

      expect(run.steps.reload.map { |step| [step.position, step.kind] }).to eq([[1, 'llm_call'], [2, 'message_sent']])
    end

    it 'rejects undocumented kinds' do
      expect { run.add_step!(kind: 'thinking') }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'deletion' do
    it 'is removed with its steps when the conversation is deleted, keeping the usage entries' do
      run.add_step!(kind: 'error')
      entry = create(:automato_agents_usage_entry, account: account, run: run)

      conversation.delete

      expect(described_class.exists?(run.id)).to be(false)
      expect(AutomatoAgents::Step.where(run_id: run.id)).to be_empty
      expect(entry.reload.run_id).to be_nil
    end
  end
end
