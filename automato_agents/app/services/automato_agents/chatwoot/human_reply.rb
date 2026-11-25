# Public replies written by a person: an agent, or the business from the native app (external
# echo). Not bots, automations, campaigns nor forwarded emails. It is the SQL form of the core
# Message#human_response? (private in Message) plus "not private", so a whole conversation is
# checked in one query; spec/automato_agents/services/automato_agents/chatwoot/human_reply_spec.rb
# pins the parity with the core method across message kinds.
class AutomatoAgents::Chatwoot::HumanReply
  def self.of(messages)
    messages.outgoing.where(private: false).where(condition)
  end

  def self.condition
    attributes = AutomatoAgents::Chatwoot::MessageAttributes
    by_person = Message.arel_table[:sender_type].eq('User').or(attributes.present_text(attributes.content_text('external_echo')))

    attributes.blank_text(attributes.content_text('forwarded_message_id'))
              .and(attributes.blank_text(attributes.content_text('automation_rule_id')))
              .and(attributes.blank_text(attributes.additional_text('campaign_id')))
              .and(by_person)
  end
  private_class_method :condition
end
