class AutomatoAgents::Usage::Recorder
  # scope accepts the optional team:, conversation: and run: the usage belongs to.
  def self.record!(account:, model:, message:, kind: 'chat', **scope)
    scope.assert_valid_keys(:team, :conversation, :run)
    entry = AutomatoAgents::UsageEntry.create!(
      account: account,
      team_id: scope[:team]&.id,
      conversation_id: scope[:conversation]&.id,
      run_id: scope[:run]&.id,
      provider: AutomatoAgents::Llm::OpenRouterProvider::PROVIDER.to_s,
      model: model,
      kind: kind,
      **usage_attributes(message.tokens, message.cost)
    )
    # an unknown cost is left out of the monthly budget (AutomatoAgents::Budget)
    Rails.logger.warn("[AutomatoAgents] usage recorded without cost account=#{account.id} usage_entry=#{entry.id}") if entry.cost_source == 'unknown'
    entry
  end

  def self.usage_attributes(tokens, cost)
    {
      input_tokens: tokens&.input.to_i,
      output_tokens: tokens&.output.to_i,
      cache_read_tokens: tokens&.cache_read.to_i,
      cache_write_tokens: tokens&.cache_write.to_i,
      thinking_tokens: tokens&.thinking.to_i,
      cost_usd: cost&.total,
      cost_source: cost_source(tokens, cost)
    }
  end
  private_class_method :usage_attributes

  def self.cost_source(tokens, cost)
    return 'reported' if tokens&.reported_cost.present?
    return 'estimated' if cost&.total.present?

    'unknown'
  end
  private_class_method :cost_source
end
