# Debounces the turns of a conversation: every new message stores a fresh token and
# enqueues a delayed TurnJob; only the job carrying the latest token runs the turn.
class AutomatoAgents::TurnScheduler
  TOKEN_TTL = 600
  DEBOUNCE_DELAY = 4.seconds

  def self.schedule(conversation)
    token = SecureRandom.uuid
    Redis::Alfred.setex(token_key(conversation.id), token, TOKEN_TTL)
    AutomatoAgents::TurnJob.set(wait: DEBOUNCE_DELAY).perform_later(conversation.id, token)
  end

  def self.current_token(conversation_id)
    Redis::Alfred.get(token_key(conversation_id))
  end

  def self.token_key(conversation_id)
    "AUTOMATO_AGENTS::TURN_TOKEN::#{conversation_id}"
  end
end
