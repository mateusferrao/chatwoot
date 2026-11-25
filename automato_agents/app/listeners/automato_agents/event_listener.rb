class AutomatoAgents::EventListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return unless turn_needed?(message)

    AutomatoAgents::TurnScheduler.schedule(message.conversation)
  end

  private

  def turn_needed?(message)
    return false unless message.incoming?
    return false if message.private?

    conversation = message.conversation
    return false unless conversation.pending?
    return false if conversation.assignee_agent_bot_id.blank?

    team = AutomatoAgents::Team.for_inbox(conversation.inbox)
    team.present? && team.agent_bot_id == conversation.assignee_agent_bot_id && team.active?
  end
end
