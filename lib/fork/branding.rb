# Marca do fork Automato (edição CE).
#
# Na edição CE não há tela para editar nome/logos da instalação: o formulário
# "custom branding" do Super Admin pertence a enterprise/. Esta classe grava
# essas configurações diretamente (código MIT) e desliga o "Powered by" do
# widget e da central de ajuda por meio da feature flag `disable_branding`.
#
# A flag é habilitada nas contas existentes e no padrão das contas novas
# (ACCOUNT_LEVEL_FEATURE_DEFAULTS), que o ConfigLoader preserva nos deploys.
#
# Uso: bundle exec rails fork:branding:apply (ver lib/tasks/fork_branding.rake)
class Fork::Branding
  BRAND_CONFIG_KEYS = %w[INSTALLATION_NAME BRAND_NAME].freeze
  URL_CONFIG_KEYS = %w[BRAND_URL WIDGET_BRAND_URL].freeze
  LOGO_CONFIG_KEYS = {
    logo: 'LOGO',
    logo_dark: 'LOGO_DARK',
    logo_thumbnail: 'LOGO_THUMBNAIL'
  }.freeze
  FEATURE_DEFAULTS_KEY = 'ACCOUNT_LEVEL_FEATURE_DEFAULTS'.freeze
  BRANDING_FEATURE = 'disable_branding'.freeze

  # logos: URLs (ou caminhos públicos) opcionais; os ausentes ficam como estão.
  def initialize(name:, url:, logos: {})
    @name = name
    @url = url
    @logos = logos.compact_blank
  end

  def apply!
    raise ArgumentError, 'O nome da marca não pode ficar vazio' if @name.blank?

    ActiveRecord::Base.transaction do
      update_configs(BRAND_CONFIG_KEYS, @name)
      update_configs(URL_CONFIG_KEYS, @url)
      update_logos
      enable_branding_feature_by_default
      enable_branding_feature_on_existing_accounts
    end
  end

  private

  # As configs são criadas pelo db:chatwoot_prepare (ConfigLoader). Exigimos que
  # já existam para preservar o atributo `locked` definido pelo upstream.
  def update_configs(keys, value)
    keys.each do |key|
      update_config(key, value)
    end
  end

  def update_logos
    @logos.each do |logo_type, value|
      update_config(LOGO_CONFIG_KEYS.fetch(logo_type), value)
    end
  end

  def update_config(key, value)
    InstallationConfig.find_by!(name: key).update!(value: value)
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
