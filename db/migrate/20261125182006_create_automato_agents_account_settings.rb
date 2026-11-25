class CreateAutomatoAgentsAccountSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :automato_agents_account_settings do |t|
      t.references :account, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.boolean :enabled, null: false, default: false
      t.string :default_model, null: false, default: 'google/gemini-3.1-flash-lite'
      t.text :fallback_message, null: false, default: 'Desculpe, tive um problema por aqui. Vou te passar para alguém da nossa equipe.'

      t.timestamps
    end
  end
end
