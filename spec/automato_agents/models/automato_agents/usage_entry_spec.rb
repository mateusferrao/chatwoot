require 'rails_helper'

RSpec.describe AutomatoAgents::UsageEntry do
  let(:entry) { build(:automato_agents_usage_entry) }

  it 'is valid with the factory defaults' do
    expect(entry).to be_valid
    expect(entry.key_source).to eq('automato')
    expect(entry.input_tokens).to eq(0)
    expect(entry.cost_usd).to be_nil
  end

  it 'only accepts the documented kinds' do
    AutomatoAgents::UsageEntry::KINDS.each do |kind|
      expect(build(:automato_agents_usage_entry, kind: kind)).to be_valid
    end
    expect(build(:automato_agents_usage_entry, kind: 'audio')).not_to be_valid
  end

  it 'only accepts the documented cost sources' do
    AutomatoAgents::UsageEntry::COST_SOURCES.each do |source|
      expect(build(:automato_agents_usage_entry, cost_source: source)).to be_valid
    end
    expect(build(:automato_agents_usage_entry, cost_source: 'guess')).not_to be_valid
  end

  it 'only accepts the documented key sources' do
    expect(build(:automato_agents_usage_entry, key_source: 'customer')).not_to be_valid
  end

  it 'keeps the cost with 8 decimal places' do
    saved = create(:automato_agents_usage_entry, cost_usd: BigDecimal('0.00012345'))

    expect(saved.reload.cost_usd).to eq(BigDecimal('0.00012345'))
  end
end
