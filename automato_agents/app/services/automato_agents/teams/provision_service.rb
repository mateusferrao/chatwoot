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
    hand_off_unserved_conversations
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

  # The link of another bot is never taken over. An active team cannot serve that inbox, so it
  # fails (Team validations reject it before saving); an inactive one skips it, so disabling the
  # team or the account always deactivates every link of the team bot.
  def attach_team_inboxes
    active = @team.active?
    @team.inboxes.each do |inbox|
      if @team.linked_to_another_bot?(inbox)
        raise AutomatoAgents::Teams::InboxBotConflictError, inbox if active

        next
      end

      agent_bot_inbox = inbox.agent_bot_inbox || AgentBotInbox.new(inbox: inbox)
      agent_bot_inbox.update!(agent_bot: @team.agent_bot, status: active ? :active : :inactive)
    end
  end

  # Customers already waiting on the bot must not stay pending once the team stops serving
  # their inbox (team or account disabled, inbox removed from the team). Runs after the
  # transaction so the handoff events are dispatched for committed state.
  def hand_off_unserved_conversations
    conversations = @team.pending_bot_conversations
    conversations = conversations.where.not(inbox_id: @team.inbox_ids) if @team.active?
    conversations.find_each(&:bot_handoff!)
  end
end
