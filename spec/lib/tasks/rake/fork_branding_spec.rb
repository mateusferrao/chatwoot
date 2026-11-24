require 'rake'
require 'rails_helper'

RSpec.describe Rake::Task do
  describe 'fork:branding:apply' do
    subject(:task) { described_class['fork:branding:apply'] }

    before { task.reenable }

    it 'applies the brand from the environment variables' do
      branding = instance_double(Fork::Branding, apply!: true)
      allow(Fork::Branding).to receive(:new).with(name: 'Minha Marca', url: 'https://minhamarca.com').and_return(branding)

      with_modified_env BRAND_NAME: 'Minha Marca', BRAND_URL: 'https://minhamarca.com' do
        expect { task.invoke }.to output(/Marca aplicada: Minha Marca/).to_stdout
      end

      expect(branding).to have_received(:apply!)
    end

    it 'defaults to the Automato brand' do
      branding = instance_double(Fork::Branding, apply!: true)
      allow(Fork::Branding).to receive(:new).with(name: 'Automato', url: 'https://automato.pro').and_return(branding)

      with_modified_env BRAND_NAME: nil, BRAND_URL: nil do
        expect { task.invoke }.to output(/Marca aplicada: Automato/).to_stdout
      end
    end
  end
end
