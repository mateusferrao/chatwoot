class AutomatoAgents::Conversations::NoActiveTeamError < StandardError
  def initialize(inbox)
    super("The inbox '#{inbox.name}' has no active agent team to answer the conversation.")
  end
end
