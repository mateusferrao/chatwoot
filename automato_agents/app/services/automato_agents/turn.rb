# One agent turn of a conversation served by a team (TurnJob checks that and holds the
# conversation lock): answers the customer messages received since the last reply, recording
# the trace (Run and Steps) and the LLM usage. On any failure the customer gets the account
# fallback message and the conversation goes to humans, so it never stays pending on the bot.
class AutomatoAgents::Turn
  # The echo agent has no tools, so one provider request answers it (see the time budget in
  # AutomatoAgents::Llm::OpenRouterProvider).
  MAX_TURNS = 1
  MAX_INPUT_MESSAGES = 20

  class BlankTextError < StandardError
  end

  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
    @team = AutomatoAgents::Team.for_inbox(conversation.inbox)
    @setting = AutomatoAgents::AccountSetting.for(@account)
  end

  def perform
    messages = pending_customer_messages
    # nothing new since the last reply: a repeated turn must not answer twice
    return if messages.empty?

    start_run(messages.last)
    answer(messages)
  rescue StandardError => e
    raise if @run.nil?

    fail_run(e)
  end

  private

  def pending_customer_messages
    last_reply_id = @conversation.messages.outgoing.where(private: false).maximum(:id)
    messages = @conversation.messages.incoming.where(private: false)
    messages = messages.where(id: (last_reply_id + 1)..) if last_reply_id
    messages.reorder(id: :desc).limit(MAX_INPUT_MESSAGES).to_a.reverse
  end

  def start_run(trigger_message)
    @run = AutomatoAgents::Run.create!(
      account: @account,
      team: @team,
      conversation: @conversation,
      status: 'running',
      trigger_message_id: trigger_message.id,
      started_at: Time.current
    )
  end

  def answer(messages)
    input = customer_text(messages)
    llm_calls = []
    result = run_agent(input, llm_calls)
    record_llm_calls(input, llm_calls)
    raise result.error if result.error
    raise BlankTextError, 'the agent returned no text' if result.output.blank?

    reply = AutomatoAgents::Chatwoot::Replier.send_text(conversation: @conversation, agent_bot: @team.agent_bot, content: result.output)
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

  # Hands off before sending the fallback message: if sending fails, the conversation is
  # already with humans and the job retry does not run the agent again.
  def fail_run(error)
    Rails.logger.error("[AutomatoAgents] turn failed run=#{@run.id} conversation=#{@conversation.id}: #{error.class}")
    @run.add_step!(kind: 'error', name: error.class.name, output: { message: error.message })
    finish_run('failed', error)
    @conversation.bot_handoff!
    AutomatoAgents::Chatwoot::Replier.send_text(conversation: @conversation, agent_bot: @team.agent_bot, content: @setting.fallback_message)
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

  def known_cost
    costs = @run.usage_entries.pluck(:cost_usd).compact
    costs.sum if costs.any?
  end
end
