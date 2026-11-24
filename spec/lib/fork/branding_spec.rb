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

  it 'preserves the locked attribute defined by the upstream configs' do
    locked_before = InstallationConfig.where(name: %w[INSTALLATION_NAME BRAND_NAME BRAND_URL WIDGET_BRAND_URL]).pluck(:name, :locked).to_h

    apply_branding

    expect(InstallationConfig.where(name: locked_before.keys).pluck(:name, :locked).to_h).to eq(locked_before)
  end

  it 'keeps the default logos when none are given' do
    expect { apply_branding }.not_to(change { config_value('LOGO') })
  end

  it 'applies the given logos and ignores blank ones' do
    described_class.new(
      name: 'Automato',
      url: 'https://automato.pro',
      logos: { logo: 'https://automato.pro/logo.svg', logo_dark: '', logo_thumbnail: 'https://automato.pro/icon.png' }
    ).apply!

    expect(config_value('LOGO')).to eq('https://automato.pro/logo.svg')
    expect(config_value('LOGO_THUMBNAIL')).to eq('https://automato.pro/icon.png')
    expect(config_value('LOGO_DARK')).to eq('/brand-assets/logo_dark.svg')
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
    2.times { described_class.new(name: 'Automato', url: 'https://automato.pro').apply! }

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
