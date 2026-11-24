require 'rails_helper'

RSpec.describe Fork::Branding do
  subject(:apply_branding) { described_class.new(name: 'Automato', url: 'https://automato.pro').apply! }

  let!(:account) { create(:account) }

  before { ConfigLoader.new.process }

  def config_value(name)
    InstallationConfig.find_by!(name: name).value
  end

  it 'applies the brand name and URL to the installation configs' do
    apply_branding

    expect(config_value('INSTALLATION_NAME')).to eq('Automato')
    expect(config_value('BRAND_NAME')).to eq('Automato')
    expect(config_value('BRAND_URL')).to eq('https://automato.pro')
    expect(config_value('WIDGET_BRAND_URL')).to eq('https://automato.pro')
  end

  it 'keeps the configs editable in super admin' do
    apply_branding

    expect(InstallationConfig.editable.pluck(:name)).to include('INSTALLATION_NAME', 'BRAND_NAME', 'BRAND_URL', 'WIDGET_BRAND_URL')
  end

  it 'disables the "Powered by" branding on existing accounts' do
    expect { apply_branding }.to change { account.reload.feature_enabled?('disable_branding') }.from(false).to(true)
  end

  it 'disables the branding on accounts created afterwards' do
    apply_branding

    expect(create(:account).feature_enabled?('disable_branding')).to be(true)
  end

  it 'keeps the feature default after the config reconciliation that runs on deploy' do
    apply_branding
    ConfigLoader.new.process

    expect(create(:account).feature_enabled?('disable_branding')).to be(true)
  end

  it 'is idempotent' do
    apply_branding

    expect { apply_branding }.not_to raise_error
    expect(config_value('BRAND_NAME')).to eq('Automato')
    expect(account.reload.feature_enabled?('disable_branding')).to be(true)
  end

  it 'rejects a blank brand name' do
    expect { described_class.new(name: ' ', url: 'https://automato.pro').apply! }.to raise_error(ArgumentError)
  end

  it 'fails visibly when the installation configs were not loaded yet' do
    InstallationConfig.where(name: 'BRAND_NAME').delete_all

    expect { apply_branding }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
