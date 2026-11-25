class AutomatoAgents::Turn
  def initialize(conversation)
    @conversation = conversation
  end

  def perform
    Rails.logger.info("[AutomatoAgents] turno conversation=#{@conversation.id}")
  end
end
