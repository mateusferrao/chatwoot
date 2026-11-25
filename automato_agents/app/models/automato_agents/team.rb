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

  before_destroy :remove_agent_bot_links
  after_commit :provision, if: :saved_change_to_enabled?, on: [:create, :update]

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validate :inboxes_belong_to_account

  def self.for_inbox(inbox)
    joins(:team_inboxes).find_by(team_inboxes: { inbox_id: inbox.id })
  end

  def active?
    enabled? && AutomatoAgents.enabled_for?(account)
  end

  # The team answers this conversation now: the team is active and the conversation is
  # pending on the team's AgentBot. Callers resolve the team from the conversation inbox.
  def serves?(conversation)
    agent_bot_id.present? &&
      conversation.pending? &&
      conversation.ai_assignee_type == 'AgentBot' &&
      conversation.assignee_agent_bot_id == agent_bot_id &&
      active?
  end

  private

  def provision
    AutomatoAgents::Teams::ProvisionService.new(self).perform
  end

  def remove_agent_bot_links
    agent_bot_inboxes.destroy_all
  end

  def inboxes_belong_to_account
    return if inboxes.all? { |inbox| inbox.account_id == account_id }

    errors.add(:inboxes, 'must belong to the same account as the team')
  end
end
