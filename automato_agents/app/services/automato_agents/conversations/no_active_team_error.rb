class AutomatoAgents::Conversations::NoActiveTeamError < StandardError
  def initialize(inbox)
    super("A caixa de entrada '#{inbox.name}' não tem uma equipe de agentes ativa para atender a conversa.")
  end
end
