class AutomatoAgents::EventListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return if message.private?

    if message.incoming?
      route_incoming(message.conversation)
    elsif human_reply?(message)
      pause_agent(message)
    end
  end

  # Resolving ends the pause, so the agent answers the conversation when it is reopened.
  def conversation_resolved(event)
    conversation = event.data[:conversation]
    AutomatoAgents::ConversationState.paused.find_by(conversation_id: conversation.id)&.activate!
  end

  private

  def route_incoming(conversation)
    return unless conversation.pending?

    route(conversation, AutomatoAgents::Team.for_inbox(conversation.inbox))
  end

  # Message#human_response? is the core definition of a reply by a person (a User, or the
  # business from the native app), not by bots, automations, campaigns nor forwards. It is
  # private in Message, hence send; the listener specs fail if it is renamed or removed.
  def human_reply?(message)
    message.send(:human_response?)
  end

  # A human (or the business, from the native app) answered the customer: the agent stops
  # answering this conversation until it is returned to the agent.
  def pause_agent(message)
    conversation = message.conversation
    return if AutomatoAgents::Team.for_inbox(conversation.inbox).nil?

    AutomatoAgents::Conversations::PauseService.new(conversation: conversation, user: message.sender).perform
  end

  # A pending conversation is either answered by the inbox team, taken by it, or handed off to
  # humans so it does not stay pending with nobody (Chatwoot reopens resolved conversations of
  # bot inboxes as pending).
  def route(conversation, team)
    return route_automato_conversation(conversation, team) if automato_bot_assigned?(conversation)
    return if team.nil?

    if conversation.assignee_id.present?
      conversation.bot_handoff!
    elsif conversation.assignee_agent_bot_id.nil?
      route_unassigned(conversation, team)
    end
  end

  # Assigned to a bot of one of our teams: answer it, or hand it off when the inbox team no
  # longer serves it (team disabled or destroyed, account disabled, inbox moved out, agent
  # paused by a human reply).
  def route_automato_conversation(conversation, team)
    if team&.serves?(conversation)
      schedule_turn(conversation)
    else
      conversation.bot_handoff!
    end
  end

  # Pending without bot nor human: the team takes it, unless the agent is paused there (e.g.
  # reopened before its resolution event was processed), which goes back to humans.
  def route_unassigned(conversation, team)
    if AutomatoAgents::ConversationState.paused?(conversation)
      conversation.bot_handoff!
    elsif team.active?
      take_over(conversation, team)
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
