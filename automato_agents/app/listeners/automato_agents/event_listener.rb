class AutomatoAgents::EventListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return unless message.incoming?
    return if message.private?

    conversation = message.conversation
    return unless conversation.pending?

    route(conversation, AutomatoAgents::Team.for_inbox(conversation.inbox))
  end

  private

  # A pending conversation is either answered by the inbox team, taken by it, or handed off to
  # humans so it does not stay pending with nobody (Chatwoot reopens resolved conversations of
  # bot inboxes as pending).
  def route(conversation, team)
    return route_automato_conversation(conversation, team) if automato_bot_assigned?(conversation)
    return if team.nil?

    if conversation.assignee_id.present?
      conversation.bot_handoff!
    elsif conversation.assignee_agent_bot_id.nil? && team.active?
      take_over(conversation, team)
    end
  end

  # Assigned to a bot of one of our teams: answer it, or hand it off when the inbox team no
  # longer serves it (team disabled or destroyed, account disabled, inbox moved out).
  def route_automato_conversation(conversation, team)
    if team&.serves?(conversation)
      schedule_turn(conversation)
    else
      conversation.bot_handoff!
    end
  end

  def automato_bot_assigned?(conversation)
    return false unless conversation.ai_assignee_type == 'AgentBot'

    agent_bot = conversation.ai_assignee
    agent_bot.present? && agent_bot.bot_config.to_h.key?('automato_agents_team_id')
  end

  def take_over(conversation, team)
    Conversations::AssignmentService.new(
      conversation: conversation,
      assignee_id: team.agent_bot_id,
      assignee_type: 'AgentBot'
    ).perform
    schedule_turn(conversation) if team.serves?(conversation)
  end

  def schedule_turn(conversation)
    AutomatoAgents::TurnScheduler.schedule(conversation)
  end
end
