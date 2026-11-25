class AddBudgetToAutomatoAgentsAccountSettings < ActiveRecord::Migration[8.0]
  def change
    change_table :automato_agents_account_settings, bulk: true do |t|
      t.decimal :monthly_budget_brl, precision: 12, scale: 2
      t.decimal :usd_brl_rate, precision: 10, scale: 4, null: false, default: 5.5
      t.string :budget_policy, null: false, default: 'handoff'
      t.string :cheaper_model, null: false, default: 'google/gemini-2.5-flash-lite'
      t.text :budget_exceeded_message, null: false, default: 'No momento vou te passar para alguém da nossa equipe, que já vai te responder.'
    end
  end
end
