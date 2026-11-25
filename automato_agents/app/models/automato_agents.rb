module AutomatoAgents
  def self.table_name_prefix
    'automato_agents_'
  end

  def self.enabled_for?(account)
    AutomatoAgents::AccountSetting.exists?(account_id: account.id, enabled: true)
  end
end
