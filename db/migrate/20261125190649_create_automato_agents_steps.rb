class CreateAutomatoAgentsSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :automato_agents_steps do |t|
      t.references :run, null: false, index: false, foreign_key: { to_table: :automato_agents_runs, on_delete: :cascade }
      t.integer :position, null: false
      t.string :kind, null: false
      t.string :name
      t.jsonb :input, null: false, default: {}
      t.jsonb :output, null: false, default: {}
      t.decimal :cost_usd, precision: 14, scale: 8
      t.integer :duration_ms
      t.datetime :created_at, null: false
    end

    add_index :automato_agents_steps, [:run_id, :position], unique: true
  end
end
