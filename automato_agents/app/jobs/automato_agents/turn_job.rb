class AutomatoAgents::TurnJob < ApplicationJob
  queue_as :automato_agents

  # a turn is budgeted to finish in 120 s (see AutomatoAgents::Llm::OpenRouterProvider)
  LOCK_TIMEOUT = 180
  LOCK_RETRY_DELAY = 5.seconds

  def perform(conversation_id, token)
    # a newer message replaced the token and enqueued its own job, or this turn already ran
    return unless AutomatoAgents::TurnScheduler.current_token(conversation_id) == token

    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil?

    performed = Redis::LockManager.new.with_lock(lock_key(conversation_id), LOCK_TIMEOUT) do
      run_turn(conversation, token)
    end
    self.class.set(wait: LOCK_RETRY_DELAY).perform_later(conversation_id, token) unless performed
  end

  private

  def run_turn(conversation, token)
    # a duplicate delivery of this job may have run the turn and consumed the token between
    # the check in #perform and taking the lock
    return unless AutomatoAgents::TurnScheduler.current_token(conversation.id) == token

    # a human may have taken over, or the team been disabled, since the turn was scheduled
    return unless AutomatoAgents::Team.for_inbox(conversation.inbox)&.serves?(conversation)

    AutomatoAgents::Turn.new(conversation).perform
    # consume only our own token so a retry of this job does not repeat the turn, while a
    # token written by a newer message during the turn keeps its job alive
    Redis::Alfred.delete_if_equals(AutomatoAgents::TurnScheduler.token_key(conversation.id), token)
  end

  def lock_key(conversation_id)
    "AUTOMATO_AGENTS::TURN_LOCK::#{conversation_id}"
  end
end
