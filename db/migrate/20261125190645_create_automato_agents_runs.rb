class CreateAutomatoAgentsRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :automato_agents_runs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :team, null: false, foreign_key: { to_table: :automato_agents_teams, on_delete: :cascade }
      t.references :conversation, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :status, null: false
      t.bigint :trigger_message_id
      t.datetime :started_at
      t.datetime :finished_at
      t.string :error_class
      t.text :error_message
      t.decimal :cost_usd, precision: 14, scale: 8
      t.timestamps
    end

    add_index :automato_agents_runs, [:conversation_id, :created_at]
  end
end
