class AutomatoAgents::Step < ApplicationRecord
  KINDS = %w[llm_call tool_call handoff message_sent guardrail budget error].freeze

  belongs_to :run, class_name: 'AutomatoAgents::Run', inverse_of: :steps

  validates :kind, inclusion: { in: KINDS }
  validates :position, presence: true
end
