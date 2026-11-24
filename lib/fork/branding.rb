# Marca do fork Automato (edição CE).
#
# Aplica o nome/URL da marca nas configurações da instalação (dashboard,
# e-mails, widget) e desliga o "Powered by" do widget e da central de ajuda
# por meio da feature flag `disable_branding`, que pertence ao código MIT.
#
# Habilita a flag nas contas existentes e no padrão das contas novas
# (ACCOUNT_LEVEL_FEATURE_DEFAULTS), que o ConfigLoader preserva nos deploys.
#
# Uso: bundle exec rails fork:branding:apply (ver lib/tasks/fork_branding.rake)
class Fork::Branding
  BRAND_CONFIG_KEYS = %w[INSTALLATION_NAME BRAND_NAME].freeze
  URL_CONFIG_KEYS = %w[BRAND_URL WIDGET_BRAND_URL].freeze
  FEATURE_DEFAULTS_KEY = 'ACCOUNT_LEVEL_FEATURE_DEFAULTS'.freeze
  BRANDING_FEATURE = 'disable_branding'.freeze

  def initialize(name:, url:)
    @name = name
    @url = url
  end

  def apply!
    raise ArgumentError, 'O nome da marca não pode ficar vazio' if @name.blank?

    ActiveRecord::Base.transaction do
      update_configs(BRAND_CONFIG_KEYS, @name)
      update_configs(URL_CONFIG_KEYS, @url)
      enable_branding_feature_by_default
      enable_branding_feature_on_existing_accounts
    end
  end

  private

  # As configs são criadas pelo db:chatwoot_prepare (ConfigLoader). Exigimos que
  # já existam para preservar o atributo `locked` definido pelo upstream.
  def update_configs(keys, value)
    keys.each do |key|
      InstallationConfig.find_by!(name: key).update!(value: value)
    end
  end

  def enable_branding_feature_by_default
    config = InstallationConfig.find_by!(name: FEATURE_DEFAULTS_KEY)
    features = config.value.map do |feature|
      feature = feature.to_h.stringify_keys
      feature['name'] == BRANDING_FEATURE ? feature.merge('enabled' => true) : feature
    end
    config.update!(value: features)
  end

  def enable_branding_feature_on_existing_accounts
    Account.find_each do |account|
      account.enable_features!(BRANDING_FEATURE) unless account.feature_enabled?(BRANDING_FEATURE)
    end
  end
end
