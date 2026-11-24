namespace :fork do
  namespace :branding do
    desc 'Aplica a marca do fork (nome/URL) e remove o "Powered by". ' \
         'Ex.: BRAND_NAME="Automato" BRAND_URL="https://automato.pro" rails fork:branding:apply'
    task apply: :environment do
      name = ENV.fetch('BRAND_NAME', 'Automato')
      url = ENV.fetch('BRAND_URL', 'https://automato.pro')

      Fork::Branding.new(name: name, url: url).apply!

      puts "Marca aplicada: #{name} (#{url}). 'Powered by' desligado em #{Account.count} conta(s) e nas contas futuras."
    end
  end
end
