class AutomatoAgents::TurnJob < ApplicationJob
  queue_as :automato_agents

  LOCK_TIMEOUT = 180
  LOCK_RETRY_DELAY = 5.seconds

  def perform(conversation_id, token)
    # a newer message replaced the token and enqueued its own job
    return unless AutomatoAgents::TurnScheduler.current_token(conversation_id) == token

    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil?

    performed = Redis::LockManager.new.with_lock(lock_key(conversation_id), LOCK_TIMEOUT) do
      AutomatoAgents::Turn.new(conversation).perform
    end
    self.class.set(wait: LOCK_RETRY_DELAY).perform_later(conversation_id, token) unless performed
  end

  private

  def lock_key(conversation_id)
    "AUTOMATO_AGENTS::TURN_LOCK::#{conversation_id}"
  end
end
