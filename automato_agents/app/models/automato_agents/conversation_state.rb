# == Schema Information
#
# Table name: automato_agents_conversation_states
#
#  id              :bigint           not null, primary key
#  paused_at       :datetime
#  status          :string           default("active"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  paused_by_id    :bigint
#  team_id         :bigint           not null
#
# Indexes
#
#  index_automato_agents_conversation_states_on_account_id       (account_id)
#  index_automato_agents_conversation_states_on_conversation_id  (conversation_id) UNIQUE
#  index_automato_agents_conversation_states_on_team_id          (team_id)
#
# Whether the agent may answer a conversation. A public human reply pauses it there until
# someone returns the conversation to the agent (Conversations::ResumeService) or it is
# resolved. Conversations without a state are active.
class AutomatoAgents::ConversationState < ApplicationRecord
  STATUSES = %w[active paused].freeze

  belongs_to :account
  belongs_to :team, class_name: 'AutomatoAgents::Team'
  belongs_to :conversation
  belongs_to :paused_by, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :paused, -> { where(status: 'paused') }

  # Callers make sure the conversation inbox is in a team. One state per conversation is
  # enforced by the unique index: concurrent callers get the row the first one created.
  def self.for(conversation)
    find_by(conversation_id: conversation.id) || create_or_find_by!(conversation_id: conversation.id) do |state|
      state.account_id = conversation.account_id
      state.team = AutomatoAgents::Team.for_inbox(conversation.inbox)
    end
  end

  def self.paused?(conversation)
    paused.exists?(conversation_id: conversation.id)
  end

  def paused?
    status == 'paused'
  end

  def pause!(user)
    update!(status: 'paused', paused_at: Time.current, paused_by: user)
  end

  def activate!
    update!(status: 'active', paused_at: nil, paused_by: nil)
  end
end
