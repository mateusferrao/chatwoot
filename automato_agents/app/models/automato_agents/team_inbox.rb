# == Schema Information
#
# Table name: automato_agents_team_inboxes
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  inbox_id   :bigint           not null
#  team_id    :bigint           not null
#
# Indexes
#
#  index_automato_agents_team_inboxes_on_inbox_id  (inbox_id) UNIQUE
#  index_automato_agents_team_inboxes_on_team_id   (team_id)
#
class AutomatoAgents::TeamInbox < ApplicationRecord
  belongs_to :team, class_name: 'AutomatoAgents::Team', inverse_of: :team_inboxes
  belongs_to :inbox

  validates :inbox_id, uniqueness: true
  validate :inbox_belongs_to_team_account

  private

  def inbox_belongs_to_team_account
    return if inbox.blank? || team.blank? || inbox.account_id == team.account_id

    errors.add(:inbox, :other_account)
  end
end
