class CreateAutomatoAgentsTeams < ActiveRecord::Migration[8.0]
  def change
    create_table :automato_agents_teams do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.boolean :enabled, null: false, default: false
      t.references :agent_bot, null: true, foreign_key: { on_delete: :nullify }

      t.timestamps
    end

    add_index :automato_agents_teams, [:account_id, :name], unique: true
  end
end
