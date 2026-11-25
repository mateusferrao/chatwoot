# Sends messages to the customer as the team AgentBot. The params go through
# ActionController::Parameters because Messages::MessageBuilder only keeps the input_select
# items from it (with a plain Hash the items store accessor is overwritten with nil).
class AutomatoAgents::Chatwoot::Replier
  # content_attributes: e.g. the AutomatoAgents::Chatwoot::ReplyMarker of an agent answer
  def self.send_text(conversation:, agent_bot:, content:, content_attributes: {})
    create_message(conversation, agent_bot, content: content, content_attributes: content_attributes)
  end

  # options: [{ title:, value: }]
  def self.send_options(conversation:, agent_bot:, content:, options:)
    create_message(
      conversation, agent_bot,
      content: content, content_type: 'input_select', content_attributes: { items: options }
    )
  end

  def self.create_message(conversation, agent_bot, **params)
    message_params = ActionController::Parameters.new(message_type: 'outgoing', **params)
    Messages::MessageBuilder.new(agent_bot, conversation, message_params).perform
  end
  private_class_method :create_message
end
