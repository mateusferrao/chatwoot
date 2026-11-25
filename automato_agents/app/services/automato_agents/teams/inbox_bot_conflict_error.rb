class AutomatoAgents::Teams::InboxBotConflictError < StandardError
  attr_reader :inbox

  def initialize(inbox)
    @inbox = inbox
    super("The inbox '#{inbox.name}' is already linked to another bot. Remove that link before adding the inbox to an agent team.")
  end
end
