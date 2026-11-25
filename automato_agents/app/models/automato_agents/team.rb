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

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validate :inboxes_belong_to_account

  def self.for_inbox(inbox)
    joins(:team_inboxes).find_by(team_inboxes: { inbox_id: inbox.id })
  end

  def active?
    enabled? && AutomatoAgents.enabled_for?(account)
  end

  private

  def inboxes_belong_to_account
    return if inboxes.all? { |inbox| inbox.account_id == account_id }

    errors.add(:inboxes, 'must belong to the same account as the team')
  end
end
