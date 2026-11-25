# Pauses the agent in a conversation a human answered publicly. A conversation still pending
# on the bot is handed off to humans the native way (opened, waiting_since and the bot handoff
# event). Repeated replies keep the first pause.
class AutomatoAgents::Conversations::PauseService
  def initialize(conversation:, user:)
    @conversation = conversation
    @user = user
  end

  def perform
    state = AutomatoAgents::ConversationState.for(@conversation)
    # paused before the handoff so a turn running now sees it when it rechecks Team#serves?
    state.pause!(@user) unless state.paused?
    @conversation.bot_handoff! if @conversation.pending?
    state
  end
end
