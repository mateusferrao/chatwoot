# == Schema Information
#
# Table name: automato_agents_teams
#
#  id           :bigint           not null, primary key
#  enabled      :boolean          default(FALSE), not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  agent_bot_id :bigint
#
# Indexes
#
#  index_automato_agents_teams_on_account_id_and_name  (account_id,name) UNIQUE
#  index_automato_agents_teams_on_agent_bot_id         (agent_bot_id)
#
class AutomatoAgents::Team < ApplicationRecord
  belongs_to :account
  belongs_to :agent_bot, optional: true
  has_many :team_inboxes, class_name: 'AutomatoAgents::TeamInbox', dependent: :destroy, inverse_of: :team
  has_many :inboxes, through: :team_inboxes
  has_many :agent_bot_inboxes, primary_key: :agent_bot_id, foreign_key: :agent_bot_id, inverse_of: false, dependent: nil
  # The runs are the audit trail of the agent (the foreign key would cascade them away): a team
  # that ran is disabled, not destroyed. Declared before the destroy callbacks so the check runs
  # first and nothing else happens.
  has_many :runs, class_name: 'AutomatoAgents::Run', dependent: :restrict_with_error, inverse_of: :team

  before_destroy :remove_agent_bot_links
  after_commit :provision, if: :saved_change_to_enabled?, on: [:create, :update]
  after_destroy_commit :hand_off_pending_conversations

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validate :inboxes_belong_to_account
  # Checked before saving an active team, so it is never left enabled with its links inactive. A
  # disabled team is not checked: disabling must always work.
  validate :inboxes_servable, if: -> { account.present? && active? }

  def self.for_inbox(inbox)
    joins(:team_inboxes).find_by(team_inboxes: { inbox_id: inbox.id })
  end

  def active?
    enabled? && AutomatoAgents.enabled_for?(account)
  end

  # The team answers this conversation now: the team is active, the conversation is pending
  # on the team's AgentBot and the agent is not paused there (a human replied). Callers
  # resolve the team from the conversation inbox.
  def serves?(conversation)
    agent_bot_id.present? &&
      conversation.pending? &&
      conversation.ai_assignee_type == 'AgentBot' &&
      conversation.assignee_agent_bot_id == agent_bot_id &&
      active? &&
      !AutomatoAgents::ConversationState.paused?(conversation)
  end

  # An inbox has a single bot link; the one of another bot is never taken over.
  def linked_to_another_bot?(inbox)
    other_bot_id = inbox.agent_bot_inbox&.agent_bot_id
    other_bot_id.present? && other_bot_id != agent_bot_id
  end

  # Why the team bot cannot serve its inboxes when active: an inbox linked to another bot, or
  # another bot provider (Dialogflow) answering it. Empty when it can.
  def serving_conflicts
    inboxes.filter_map do |inbox|
      if linked_to_another_bot?(inbox)
        I18n.t('automato_agents.errors.inbox_linked_to_another_bot', inbox: inbox.name)
      elsif (provider = inbox.conflicting_bot_provider(:agent_bot))
        "#{inbox.name}: #{I18n.t('errors.inboxes.bot_provider_conflict', current_provider: provider, requested_provider: 'Agent Bot')}"
      end
    end
  end

  def pending_bot_conversations
    Conversation.pending.where(account_id: account_id, ai_assignee_type: 'AgentBot', assignee_agent_bot_id: agent_bot_id)
  end

  private

  def provision
    AutomatoAgents::Teams::ProvisionService.new(self).perform
  end

  def remove_agent_bot_links
    agent_bot_inboxes.destroy_all
  end

  # Customers waiting on the bot of a destroyed team go to humans now, not on their next message.
  def hand_off_pending_conversations
    return if agent_bot_id.blank?

    pending_bot_conversations.find_each(&:bot_handoff!)
  end

  def inboxes_belong_to_account
    return if inboxes.all? { |inbox| inbox.account_id == account_id }

    errors.add(:inboxes, :other_account)
  end

  def inboxes_servable
    serving_conflicts.each { |conflict| errors.add(:base, conflict) }
  end
end
