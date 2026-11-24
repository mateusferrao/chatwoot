namespace :fork do
  namespace :branding do
    desc 'Aplica a marca do fork (nome, URL e logos opcionais) e remove o "Powered by". ' \
         'Ex.: BRAND_NAME="Automato" BRAND_URL="https://automato.pro" LOGO_URL="https://.../logo.svg" rails fork:branding:apply'
    task apply: :environment do
      name = ENV.fetch('BRAND_NAME', 'Automato')
      url = ENV.fetch('BRAND_URL', 'https://automato.pro')
      logos = {
        logo: ENV.fetch('LOGO_URL', nil),
        logo_dark: ENV.fetch('LOGO_DARK_URL', nil),
        logo_thumbnail: ENV.fetch('LOGO_THUMBNAIL_URL', nil)
      }

      Fork::Branding.new(name: name, url: url, logos: logos).apply!

      puts "Marca aplicada: #{name} (#{url}). 'Powered by' desligado em #{Account.count} conta(s) e nas contas futuras."
    end
  end
end
