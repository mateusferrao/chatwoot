# == Schema Information
#
# Table name: automato_agents_account_settings
#
#  id               :bigint           not null, primary key
#  default_model    :string           default("google/gemini-3.1-flash-lite"), not null
#  enabled          :boolean          default(FALSE), not null
#  fallback_message :text             default("Desculpe, tive um problema por aqui. Vou te passar para alguém da nossa equipe."), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_automato_agents_account_settings_on_account_id  (account_id) UNIQUE
#
class AutomatoAgents::AccountSetting < ApplicationRecord
  belongs_to :account

  validates :account_id, uniqueness: true

  def self.for(account)
    find_or_initialize_by(account_id: account.id)
  end
end
