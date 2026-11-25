class AutomatoAgents::Run < ApplicationRecord
  STATUSES = %w[running succeeded failed].freeze

  belongs_to :account
  belongs_to :team, class_name: 'AutomatoAgents::Team'
  belongs_to :conversation
  has_many :steps, -> { order(:position) }, class_name: 'AutomatoAgents::Step', dependent: :destroy, inverse_of: :run
  has_many :usage_entries, class_name: 'AutomatoAgents::UsageEntry', dependent: :nullify, inverse_of: :run

  validates :status, inclusion: { in: STATUSES }

  def add_step!(kind:, **attributes)
    steps.create!(position: steps.maximum(:position).to_i + 1, kind: kind, **attributes)
  end
end
