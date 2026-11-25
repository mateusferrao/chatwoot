class AutomatoAgents::Teams::ProvisionService
  BOT_DESCRIPTION = 'Automato Agents'.freeze

  def initialize(team)
    @team = team
  end

  def perform
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
    AgentBotInbox.where(agent_bot_id: @team.agent_bot_id).where.not(inbox_id: @team.inbox_ids).destroy_all
  end

  def attach_team_inboxes
    @team.inboxes.each do |inbox|
      agent_bot_inbox = inbox.agent_bot_inbox || AgentBotInbox.new(inbox: inbox)
      agent_bot_inbox.agent_bot = @team.agent_bot
      agent_bot_inbox.status = :active
      agent_bot_inbox.save!
    end
  end
end
