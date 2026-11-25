# Agents::Runner (ai-agents 0.14.0) builds every chat, the first one and the one after each
# handoff, from the global RubyLLM configuration, which has no OpenRouter key. This runner
# builds them from the given RubyLLM context instead, so each request carries the account key
# and time budget. spec/automato_agents/lib/automato_agents/llm/context_runner_spec.rb pins the
# ai-agents internals it relies on.
class AutomatoAgents::Llm::ContextRunner < Agents::Runner
  def initialize(llm_context)
    super()
    @llm_context = llm_context
  end

  private

  def build_chat(agent)
    @llm_context.chat(
      model: agent.model,
      provider: agent.provider,
      protocol: agent.protocol,
      assume_model_exists: agent.assume_model_exists
    )
  end
end
