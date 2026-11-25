class CreateAutomatoAgentsUsageEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :automato_agents_usage_entries do |t|
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.bigint :team_id
      t.bigint :conversation_id
      t.string :provider, null: false
      t.string :model, null: false
      t.string :kind, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cache_read_tokens, null: false, default: 0
      t.integer :cache_write_tokens, null: false, default: 0
      t.integer :thinking_tokens, null: false, default: 0
      t.decimal :cost_usd, precision: 14, scale: 8
      t.string :cost_source, null: false
      t.string :key_source, null: false, default: 'automato'
      t.datetime :created_at, null: false
    end

    add_index :automato_agents_usage_entries, [:account_id, :created_at]
  end
end
