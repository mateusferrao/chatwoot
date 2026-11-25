class AutomatoAgents::Usage::Recorder
  # scope accepts the optional team: and conversation: the usage belongs to.
  def self.record!(account:, model:, message:, kind: 'chat', **scope)
    scope.assert_valid_keys(:team, :conversation)
    tokens = message.tokens
    cost = message.cost

    AutomatoAgents::UsageEntry.create!(
      account: account,
      team_id: scope[:team]&.id,
      conversation_id: scope[:conversation]&.id,
      provider: AutomatoAgents::Llm::OpenRouterProvider::PROVIDER.to_s,
      model: model,
      kind: kind,
      input_tokens: tokens&.input.to_i,
      output_tokens: tokens&.output.to_i,
      cache_read_tokens: tokens&.cache_read.to_i,
      cache_write_tokens: tokens&.cache_write.to_i,
      thinking_tokens: tokens&.thinking.to_i,
      cost_usd: cost&.total,
      cost_source: cost_source(tokens, cost)
    )
  end

  def self.cost_source(tokens, cost)
    return 'reported' if tokens&.reported_cost.present?
    return 'estimated' if cost&.total.present?

    'unknown'
  end
  private_class_method :cost_source
end
