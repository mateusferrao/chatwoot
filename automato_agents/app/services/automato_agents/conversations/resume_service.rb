# Returns a conversation to the agent ("devolver ao agente"): the agent is active there again
# and the conversation goes back to pending on the bot of the inbox team.
class AutomatoAgents::Conversations::ResumeService
  def initialize(conversation:, user:)
    @conversation = conversation
    @user = user
  end

  def perform
    team = AutomatoAgents::Team.for_inbox(@conversation.inbox)
    raise AutomatoAgents::Conversations::NoActiveTeamError, @conversation.inbox unless team&.active? && team.agent_bot_id.present?

    ActiveRecord::Base.transaction do
      AutomatoAgents::ConversationState.for(@conversation).activate!
      Conversations::AssignmentService.new(conversation: @conversation, assignee_id: team.agent_bot_id, assignee_type: 'AgentBot').perform
    end
    Rails.logger.info("[AutomatoAgents] conversation=#{@conversation.id} returned to the agent by user=#{@user&.id}")
    @conversation
  end
end
