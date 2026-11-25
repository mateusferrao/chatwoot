# One agent turn of a conversation served by a team (TurnJob checks that and holds the
# conversation lock): answers the customer messages not answered yet, recording the trace (Run
# and Steps) and the LLM usage. On any failure the customer gets the account fallback message
# and the conversation goes to humans, so it never stays pending on the bot.
class AutomatoAgents::Turn
  # The echo agent has no tools, so one provider request answers it (see the time budget in
  # AutomatoAgents::Llm::OpenRouterProvider).
  MAX_TURNS = 1
  MAX_INPUT_MESSAGES = 20

  class BlankTextError < StandardError
  end

  # A human took over, the conversation was resolved, or the team or account was disabled
  # while the agent was thinking: the agent must stay silent.
  class NoLongerServedError < StandardError
  end

  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
    @team = AutomatoAgents::Team.for_inbox(conversation.inbox)
    @setting = AutomatoAgents::AccountSetting.for(@account)
  end

  def perform
    messages = unanswered_customer_messages
    # nothing new since the last answer: a repeated turn must not answer twice
    return if messages.empty?

    start_run(messages.last)
    run_turn(messages)
  end

  private

  # Incoming messages after the last one an earlier run answered, or after the last reply of
  # someone other than this team's bot (a human). Messages that arrive while a turn runs are
  # left for the next turn. Failed and interrupted runs do not count as answers.
  def unanswered_customer_messages
    messages = @conversation.messages.incoming.where(private: false)
    answered_through = [last_answered_message_id, last_reply_by_others_id].compact.max
    messages = messages.where(id: (answered_through + 1)..) if answered_through
    messages.reorder(id: :desc).limit(MAX_INPUT_MESSAGES).to_a.reverse
  end

  def last_answered_message_id
    AutomatoAgents::Run.where(conversation_id: @conversation.id, status: 'succeeded').maximum(:trigger_message_id)
  end

  def last_reply_by_others_id
    table = Message.arel_table
    not_from_team_bot = table[:sender_type].is_distinct_from('AgentBot').or(table[:sender_id].is_distinct_from(@team.agent_bot_id))
    @conversation.messages.outgoing.where(private: false).where(not_from_team_bot).maximum(:id)
  end

  # trigger_message_id is the last customer message this run answers
  def start_run(last_message)
    @run = AutomatoAgents::Run.create!(
      account: @account,
      team: @team,
      conversation: @conversation,
      status: 'running',
      trigger_message_id: last_message.id,
      started_at: Time.current
    )
  end

  def run_turn(messages)
    answer(messages)
  rescue StandardError => e
    fail_run(e)
  ensure
    # an interruption (e.g. Sidekiq shutdown) or a failure while failing must not leave the run running
    mark_interrupted($ERROR_INFO) if @run.status_in_database == 'running'
  end

  def answer(messages)
    input = customer_text(messages)
    llm_calls = []
    result = run_agent(input, llm_calls)
    record_llm_calls(input, llm_calls)
    raise result.error if result.error
    raise BlankTextError, 'the agent returned no text' if result.output.blank?
    raise NoLongerServedError, 'the conversation is no longer served by the team' unless still_served?

    reply = AutomatoAgents::Chatwoot::Replier.send_text(conversation: @conversation, agent_bot: @team.agent_bot, content: result.output)
    @reply_sent = true
    @run.add_step!(kind: 'message_sent', name: 'send_text', output: { message_id: reply.id, content: reply.content })
    finish_run('succeeded')
  end

  def customer_text(messages)
    text = messages.filter_map { |message| message.content.presence }.join("\n")
    raise BlankTextError, 'the customer messages have no text' if text.blank?

    text
  end

  # The callback only collects in memory: ai-agents swallows callback exceptions, so the usage
  # is persisted afterwards, where a failure reaches the fallback path.
  def run_agent(input, llm_calls)
    # resolved before running so a missing key raises here, without any request
    llm_context = AutomatoAgents::Llm::OpenRouterProvider.new(account: @account).context
    agent = AutomatoAgents::Agents::EchoBuilder.build(@setting)
    collect_llm_call = proc do |_agent_name, model, response|
      llm_calls << { model: model, response: response, finished_at: Time.current }
    end

    AutomatoAgents::Llm::ContextRunner.new(llm_context).run(
      agent, input,
      registry: { agent.name => agent },
      max_turns: MAX_TURNS,
      callbacks: { llm_call_complete: [collect_llm_call] }
    )
  end

  def record_llm_calls(input, llm_calls)
    previous_finish = @run.started_at
    llm_calls.each do |call|
      record_llm_call(input, call, previous_finish)
      previous_finish = call[:finished_at]
    end
  end

  def record_llm_call(input, call, previous_finish)
    response = call[:response]
    entry = AutomatoAgents::Usage::Recorder.record!(
      account: @account, model: call[:model], message: response, team: @team, conversation: @conversation, run: @run
    )
    @run.add_step!(
      kind: 'llm_call',
      name: call[:model],
      input: { text: input },
      output: { content: response.content, input_tokens: entry.input_tokens, output_tokens: entry.output_tokens },
      cost_usd: entry.cost_usd,
      duration_ms: ((call[:finished_at] - previous_finish) * 1000).round
    )
  end

  # The customer is told and handed to humans only while the team still serves the conversation
  # and has not answered it yet. The fallback goes first because a bot message clears
  # waiting_since; the handoff sets it again even when sending fails.
  def fail_run(error)
    Rails.logger.error("[AutomatoAgents] turn failed run=#{@run.id} conversation=#{@conversation.id}: #{error.class}")
    hand_off_with_fallback if !@reply_sent && still_served?
    @run.add_step!(kind: 'error', name: error.class.name, output: { message: error.message })
    finish_run('failed', error)
  end

  def hand_off_with_fallback
    AutomatoAgents::Chatwoot::Replier.send_text(conversation: @conversation, agent_bot: @team.agent_bot, content: @setting.fallback_message)
  ensure
    @conversation.reload.bot_handoff!
  end

  def still_served?
    @conversation.reload
    @team.reload.serves?(@conversation)
  end

  def finish_run(status, error = nil)
    @run.update!(
      status: status,
      finished_at: Time.current,
      cost_usd: known_cost,
      error_class: error&.class&.name,
      error_message: error&.message
    )
  end

  # error is nil when the thread was killed without an exception
  def mark_interrupted(error)
    @run.update!(status: 'failed', finished_at: Time.current, error_class: error&.class&.name || 'Interrupted', error_message: error&.message)
  end

  def known_cost
    costs = @run.usage_entries.pluck(:cost_usd).compact
    costs.sum if costs.any?
  end
end
