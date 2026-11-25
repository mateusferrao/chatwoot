class CreateAutomatoAgentsConversationStates < ActiveRecord::Migration[8.0]
  def change
    create_table :automato_agents_conversation_states do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :team, null: false, foreign_key: { to_table: :automato_agents_teams, on_delete: :cascade }
      t.references :conversation, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: 'active'
      t.datetime :paused_at
      t.bigint :paused_by_id
      t.timestamps
    end
  end
end
