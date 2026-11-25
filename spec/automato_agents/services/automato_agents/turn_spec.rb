require 'rails_helper'

RSpec.describe AutomatoAgents::Turn do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:automato_agents_team, account: account) }
  let(:agent_bot) { team.reload.agent_bot }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: create(:contact_inbox, inbox: inbox)).reload }
  let(:api_key) { 'test-account-openrouter-key' }
  let(:model) { 'google/gemini-3.1-flash-lite' }
  let(:fallback_message) { 'Opa, deu um problema. Já chamo alguém da equipe.' }
  let(:completions_url) { 'https://openrouter.ai/api/v1/chat/completions' }
  let(:agent_reply) { 'Entendi, você quer saber se abrimos no sábado.' }
  let(:response_body) do
    {
      id: 'gen-1', object: 'chat.completion', model: model,
      choices: [{ index: 0, finish_reason: 'stop', message: { role: 'assistant', content: agent_reply } }],
      usage: { prompt_tokens: 40, completion_tokens: 12, total_tokens: 52, cost: 0.00012345 }
    }
  end
  let!(:completion_stub) do
    stub_request(:post, completions_url)
      .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  before do
    create(:automato_agents_team_inbox, team: team, inbox: inbox)
    create(:automato_agents_account_setting, account: account, enabled: true, fallback_message: fallback_message)
    team.update!(enabled: true)
  end

  after do
    Redis::Alfred.delete(AutomatoAgents::TurnScheduler.token_key(conversation.id))
  end

  # Creates the message and runs the real event pipeline up to the scheduled (debounced) turn job.
  def deliver(content)
    perform_enqueued_jobs(only: EventDispatcherJob) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
    end
  end

  def run_scheduled_turns
    with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key do
      perform_enqueued_jobs(only: AutomatoAgents::TurnJob)
    end
  end

  def bot_replies
    conversation.messages.outgoing.where(sender: agent_bot).order(:id)
  end

  def user_text_sent_to_model(request)
    JSON.parse(request.body)['messages'].select { |message| message['role'] == 'user' }.map do |message|
      Array(message['content']).map { |part| part.is_a?(Hash) ? part['text'] : part }.join
    end
  end

  def expect_failed_turn(error_class)
    run = AutomatoAgents::Run.last
    expect(run).to have_attributes(status: 'failed', error_class: error_class, finished_at: be_present)
    expect(run.steps.map(&:kind)).to eq(['error'])
    expect(bot_replies.map(&:content)).to eq([fallback_message])
    expect(conversation.reload).to have_attributes(status: 'open', ai_assignee: nil, assignee_agent_bot_id: nil, waiting_since: be_present)
  end

  # Answers every OpenRouter request; the first one also runs the given block, as if it
  # happened while the agent was thinking.
  def stub_completion_while_thinking(status: 200)
    calls = 0
    stub_request(:post, completions_url).to_return do
      calls += 1
      yield if calls == 1
      { status: status, body: (status == 200 ? response_body : { error: { message: 'upstream down' } }).to_json,
        headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def human_takes_over
    Conversations::AssignmentService.new(conversation: Conversation.find(conversation.id), assignee_id: create(:user, account: account).id).perform
  end

  describe 'answering the customer' do
    it 'replies as the team AgentBot with the agent output in a succeeded run' do
      deliver('Vocês abrem no sábado?')
      run_scheduled_turns

      expect(bot_replies.map(&:content)).to eq([agent_reply])
      expect(AutomatoAgents::Run.sole).to have_attributes(
        status: 'succeeded', account_id: account.id, team_id: team.id, conversation_id: conversation.id,
        trigger_message_id: conversation.messages.incoming.last.id, error_class: nil,
        started_at: be_present, finished_at: be_present, cost_usd: BigDecimal('0.00012345')
      )
      expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: agent_bot.id)
    end

    it 'records the llm_call and message_sent steps and the usage entry of the run' do
      deliver('Vocês abrem no sábado?')
      run_scheduled_turns

      run = AutomatoAgents::Run.sole
      expect(run.steps.map { |step| [step.position, step.kind] }).to eq([[1, 'llm_call'], [2, 'message_sent']])
      expect(run.steps.first).to have_attributes(
        name: model, input: { 'text' => 'Vocês abrem no sábado?' }, cost_usd: BigDecimal('0.00012345'), duration_ms: be >= 0
      )
      expect(run.steps.second.output).to eq('message_id' => bot_replies.first.id, 'content' => agent_reply)
      expect(AutomatoAgents::UsageEntry.sole).to have_attributes(
        run_id: run.id, team_id: team.id, conversation_id: conversation.id, model: model,
        input_tokens: 40, output_tokens: 12, cost_source: 'reported'
      )
    end

    it 'calls OpenRouter with the account key and leaves the global RubyLLM configuration untouched' do
      global_key = RubyLLM.config.openrouter_api_key

      deliver('Oi')
      run_scheduled_turns

      expect(
        completion_stub.with(headers: { 'Authorization' => "Bearer #{api_key}" }) { |req| JSON.parse(req.body)['model'] == model }
      ).to have_been_requested.once
      expect(RubyLLM.config.openrouter_api_key).to eq(global_key)
      expect(RubyLLM.config.openrouter_api_key).not_to eq(api_key)
    end

    it 'answers a burst of two messages once, sending both to the model' do
      deliver('Oi')
      deliver('tudo bem?')
      run_scheduled_turns

      expect(bot_replies.count).to eq(1)
      expect(AutomatoAgents::Run.count).to eq(1)
      expect(completion_stub.with { |req| user_text_sent_to_model(req) == ["Oi\ntudo bem?"] }).to have_been_requested.once
    end

    it 'only sends the customer messages received after the last reply' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Antiga')
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Resposta')
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Nota', private: true)
      deliver('Nova')
      run_scheduled_turns

      expect(completion_stub.with { |req| user_text_sent_to_model(req) == ['Nova'] }).to have_been_requested.once
    end

    it 'sends at most the 20 latest customer messages, in order' do
      (1..21).each do |number|
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: "m#{number}")
      end

      with_modified_env(AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key) { described_class.new(conversation).perform }

      expected_text = (2..21).map { |number| "m#{number}" }.join("\n")
      expect(completion_stub.with { |req| user_text_sent_to_model(req) == [expected_text] }).to have_been_requested.once
    end

    it 'does not schedule a new turn for its own reply' do
      deliver('Oi')
      run_scheduled_turns
      expect(bot_replies.count).to eq(1)

      perform_enqueued_jobs(only: EventDispatcherJob)

      expect(AutomatoAgents::TurnJob).not_to have_been_enqueued
      expect(Redis::Alfred.get(AutomatoAgents::TurnScheduler.token_key(conversation.id))).to be_nil
    end
  end

  describe 'messages that arrive during a turn' do
    it 'answers them in the next turn instead of dropping them' do
      stub_completion_while_thinking { deliver('E no domingo?') }

      deliver('Vocês abrem no sábado?')
      run_scheduled_turns
      run_scheduled_turns

      expect(bot_replies.count).to eq(2)
      expect(AutomatoAgents::Run.order(:id).map(&:status)).to eq(%w[succeeded succeeded])
      expect(a_request(:post, completions_url).with { |req| user_text_sent_to_model(req) == ['Vocês abrem no sábado?'] }).to have_been_made.once
      expect(a_request(:post, completions_url).with { |req| user_text_sent_to_model(req) == ['E no domingo?'] }).to have_been_made.once
    end
  end

  describe 'conversations no longer served while the agent thinks' do
    it 'does not reply when a human took over' do
      stub_completion_while_thinking { human_takes_over }

      deliver('Oi')
      run_scheduled_turns

      expect(bot_replies).to be_empty
      expect(AutomatoAgents::Run.sole).to have_attributes(status: 'failed', error_class: 'AutomatoAgents::Turn::NoLongerServedError')
      expect(conversation.reload).to have_attributes(status: 'open', assignee_agent_bot_id: nil)
    end

    it 'does not reply when the team was disabled' do
      stub_completion_while_thinking { team.reload.update!(enabled: false) }

      deliver('Oi')
      run_scheduled_turns

      expect(bot_replies).to be_empty
      expect(AutomatoAgents::Run.sole.error_class).to eq('AutomatoAgents::Turn::NoLongerServedError')
    end

    it 'sends no fallback when the AI fails after a human took over' do
      stub_completion_while_thinking(status: 500) { human_takes_over }

      deliver('Oi')
      run_scheduled_turns

      expect(bot_replies).to be_empty
      expect(AutomatoAgents::Run.sole).to have_attributes(status: 'failed', error_class: 'RubyLLM::ServerError')
      expect(conversation.reload.assignee).to be_present
    end
  end

  describe 'idempotency' do
    it 'answers once when the turn runs twice in a row, without a second run nor AI call' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi')

      with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key do
        2.times { described_class.new(conversation).perform }
      end

      expect(bot_replies.count).to eq(1)
      expect(AutomatoAgents::Run.count).to eq(1)
      expect(completion_stub).to have_been_requested.once
    end

    it 'does nothing without customer messages after the last reply' do
      expect { described_class.new(conversation).perform }.not_to change(AutomatoAgents::Run, :count)

      expect(bot_replies).to be_empty
      expect(completion_stub).not_to have_been_requested
    end
  end

  describe 'failures' do
    it 'sends the fallback message and hands off to humans when OpenRouter fails' do
      error_body = { error: { message: 'upstream down' } }.to_json
      stub_request(:post, completions_url).to_return(status: 500, body: error_body, headers: { 'Content-Type' => 'application/json' })

      deliver('Oi')
      run_scheduled_turns

      expect_failed_turn('RubyLLM::ServerError')
      expect(AutomatoAgents::Run.last.error_message).to be_present
    end

    context 'without the OpenRouter key' do
      let(:api_key) { nil }

      it 'takes the same failure path without any request to OpenRouter' do
        deliver('Oi')
        run_scheduled_turns

        expect_failed_turn('AutomatoAgents::Llm::MissingApiKeyError')
        expect(a_request(:post, completions_url)).not_to have_been_made
      end
    end

    it 'hands off customer messages without text (e.g. only an attachment) without calling the model' do
      deliver(nil)
      run_scheduled_turns

      expect_failed_turn('AutomatoAgents::Turn::BlankTextError')
      expect(completion_stub).not_to have_been_requested
    end

    it 'only records the failure when it happens after the reply was sent' do
      allow(AutomatoAgents::Run).to receive(:create!).and_wrap_original do |create_run, **attributes|
        create_run.call(**attributes).tap do |run|
          allow(run).to receive(:add_step!).and_wrap_original do |add_step, **step|
            raise ActiveRecord::ActiveRecordError, 'trace write failed' if step[:kind] == 'message_sent'

            add_step.call(**step)
          end
        end
      end

      deliver('Oi')
      run_scheduled_turns

      expect(bot_replies.map(&:content)).to eq([agent_reply])
      expect(AutomatoAgents::Run.sole).to have_attributes(status: 'failed', error_class: 'ActiveRecord::ActiveRecordError')
      expect(conversation.reload).to have_attributes(status: 'pending', assignee_agent_bot_id: agent_bot.id)
    end

    it 'marks the run as failed and re-raises when the worker is interrupted mid-turn' do
      stub_request(:post, completions_url).to_raise(Interrupt)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi')

      with_modified_env AUTOMATO_AGENTS_OPENROUTER_API_KEY: api_key do
        expect { described_class.new(conversation).perform }.to raise_error(Interrupt)
      end

      expect(AutomatoAgents::Run.sole).to have_attributes(status: 'failed', error_class: 'Interrupt', finished_at: be_present)
      expect(bot_replies).to be_empty
    end

    it 'does not run the agent again once the failed turn handed the conversation off' do
      stub_request(:post, completions_url).to_return(status: 500, body: '{}', headers: { 'Content-Type' => 'application/json' })
      deliver('Oi')
      run_scheduled_turns

      deliver('Alguém aí?')
      run_scheduled_turns

      expect(AutomatoAgents::Run.count).to eq(1)
      expect(bot_replies.count).to eq(1)
    end
  end
end
