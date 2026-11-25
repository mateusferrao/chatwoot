class AutomatoAgents::Teams::InboxBotConflictError < StandardError
  def initialize(inbox)
    super("A caixa de entrada '#{inbox.name}' já está ligada a outro bot. Remova o vínculo atual antes de adicioná-la a uma equipe de agentes.")
  end
end
