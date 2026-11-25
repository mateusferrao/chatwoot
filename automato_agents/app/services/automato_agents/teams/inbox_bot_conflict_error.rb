class AutomatoAgents::Teams::InboxBotConflictError < StandardError
  def initialize(inbox)
    super("The inbox '#{inbox.name}' is already linked to another bot. Remove that link before adding the inbox to an agent team.")
  end
end
