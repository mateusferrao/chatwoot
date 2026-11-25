class CreateAutomatoAgentsTeamInboxes < ActiveRecord::Migration[8.0]
  def change
    create_table :automato_agents_team_inboxes do |t|
      t.references :team, null: false, foreign_key: { to_table: :automato_agents_teams, on_delete: :cascade }
      t.references :inbox, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
  end
end
