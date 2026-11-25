# Marks each message the team bot sends to the customer with the last customer message it
# answers, in the message itself. The answer and its marker are written together, so a turn
# interrupted after sending (e.g. Sidekiq shutdown before the run is finished) is not answered
# again when the job is retried.
class AutomatoAgents::Chatwoot::ReplyMarker
  KEY = 'automato_agents'.freeze

  def self.content_attributes(run_id:, answered_through:)
    { KEY => { 'run_id' => run_id, 'answered_through' => answered_through } }
  end

  # A turn only answers customer messages after the last answered one, so the latest marked
  # message of the bot holds the highest marker: only that message is read.
  def self.last_answered_message_id(conversation, agent_bot_id)
    answered_through = answered_through_column
    conversation.messages.outgoing
                .where(sender_type: 'AgentBot', sender_id: agent_bot_id)
                .where(answered_through.not_eq(nil))
                .reorder(id: :desc)
                .pick(answered_through)
  end

  # Message stores content_attributes (a json column) through the JSON coder, so the column
  # holds a JSON-encoded string: #>> '{}' unwraps it before reading the marker, as
  # Message.not_forwarded does.
  def self.answered_through_column
    attributes = Arel::Nodes::InfixOperation.new('#>>', Message.arel_table[:content_attributes], Arel::Nodes.build_quoted('{}'))
    answered_through = Arel::Nodes::InfixOperation.new('#>>', cast(attributes, 'jsonb'), Arel::Nodes.build_quoted("{#{KEY},answered_through}"))
    cast(answered_through, 'bigint')
  end
  private_class_method :answered_through_column

  def self.cast(expression, type)
    Arel::Nodes::NamedFunction.new('CAST', [expression.as(type)])
  end
  private_class_method :cast
end
