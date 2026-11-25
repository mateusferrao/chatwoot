class AddRunIdToAutomatoAgentsUsageEntries < ActiveRecord::Migration[8.0]
  def change
    add_reference :automato_agents_usage_entries, :run, foreign_key: { to_table: :automato_agents_runs, on_delete: :nullify }
  end
end
