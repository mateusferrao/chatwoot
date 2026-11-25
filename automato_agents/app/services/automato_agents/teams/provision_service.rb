class AutomatoAgents::Teams::ProvisionService
  BOT_DESCRIPTION = 'Automato Agents'.freeze

  def initialize(team)
    @team = team
  end

  def perform
    @team.reload
    ActiveRecord::Base.transaction do
      ensure_agent_bot
      detach_removed_inboxes
      attach_team_inboxes
    end
    @team
  end

  private

  def ensure_agent_bot
    return if @team.agent_bot.present?

    agent_bot = @team.account.agent_bots.create!(
      name: @team.name,
      description: BOT_DESCRIPTION,
      bot_config: { 'automato_agents_team_id' => @team.id }
    )
    @team.update!(agent_bot: agent_bot)
  end

  def detach_removed_inboxes
    @team.agent_bot_inboxes.where.not(inbox_id: @team.inbox_ids).destroy_all
  end

  def attach_team_inboxes
    status = @team.active? ? :active : :inactive
    @team.inboxes.each do |inbox|
      agent_bot_inbox = inbox.agent_bot_inbox || AgentBotInbox.new(inbox: inbox)
      ensure_not_linked_to_another_bot(agent_bot_inbox)
      agent_bot_inbox.update!(agent_bot: @team.agent_bot, status: status)
    end
  end

  def ensure_not_linked_to_another_bot(agent_bot_inbox)
    other_bot_id = agent_bot_inbox.agent_bot_id
    return if other_bot_id.blank? || other_bot_id == @team.agent_bot_id

    raise AutomatoAgents::Teams::InboxBotConflictError, agent_bot_inbox.inbox
  end
end
