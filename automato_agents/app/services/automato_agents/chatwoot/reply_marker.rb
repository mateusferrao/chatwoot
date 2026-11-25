# Marks each message the team bot sends to the customer with the last customer message it
# answers, in the message itself. The answer and its marker are written together, so a turn
# interrupted after sending (e.g. Sidekiq shutdown before the run is finished) is not answered
# again when the job is retried.
class AutomatoAgents::Chatwoot::ReplyMarker
  KEY = 'automato_agents'.freeze

  def self.content_attributes(run_id:, answered_through:)
    { KEY => { 'run_id' => run_id, 'answered_through' => answered_through } }
  end

  # The highest marker of the bot messages in the conversation, whatever order they were sent in.
  def self.last_answered_message_id(conversation, agent_bot_id)
    conversation.messages.outgoing.where(sender_type: 'AgentBot', sender_id: agent_bot_id).maximum(answered_through_column)
  end

  def self.answered_through_column
    attributes = AutomatoAgents::Chatwoot::MessageAttributes
    attributes.cast(attributes.content_text(KEY, 'answered_through'), 'bigint')
  end
  private_class_method :answered_through_column
end
