# == Schema Information
#
# Table name: automato_agents_usage_entries
#
#  id                 :bigint           not null, primary key
#  cache_read_tokens  :integer          default(0), not null
#  cache_write_tokens :integer          default(0), not null
#  cost_source        :string           not null
#  cost_usd           :decimal(14, 8)
#  created_at         :datetime         not null
#  input_tokens       :integer          default(0), not null
#  key_source         :string           default("automato"), not null
#  kind               :string           not null
#  model              :string           not null
#  output_tokens      :integer          default(0), not null
#  provider           :string           not null
#  thinking_tokens    :integer          default(0), not null
#  account_id         :bigint           not null
#  conversation_id    :bigint
#  team_id            :bigint
#
# Indexes
#
#  idx_on_account_id_created_at_f49dd83df0  (account_id,created_at)
#
class AutomatoAgents::UsageEntry < ApplicationRecord
  KINDS = %w[chat embedding transcription vision].freeze
  COST_SOURCES = %w[reported estimated unknown].freeze
  KEY_SOURCES = %w[automato].freeze

  belongs_to :account
  belongs_to :run, class_name: 'AutomatoAgents::Run', optional: true, inverse_of: :usage_entries

  validates :provider, :model, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :cost_source, inclusion: { in: COST_SOURCES }
  validates :key_source, inclusion: { in: KEY_SOURCES }
end
