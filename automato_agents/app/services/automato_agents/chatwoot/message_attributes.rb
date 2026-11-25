# Arel expressions over the JSON attributes of messages, in the shape Postgres stores them.
# Message stores content_attributes (a json column) through the JSON coder, so the column holds a
# JSON-encoded string: #>> '{}' unwraps it before reading a key, as Message.not_forwarded does.
# additional_attributes is a plain jsonb column.
module AutomatoAgents::Chatwoot::MessageAttributes
  # the text at the given path of content_attributes (SQL NULL when missing or JSON null)
  def self.content_text(*path)
    unwrapped = Arel::Nodes::InfixOperation.new('#>>', Message.arel_table[:content_attributes], Arel::Nodes.build_quoted('{}'))
    text_at(cast(unwrapped, 'jsonb'), path)
  end

  # the text at the given path of additional_attributes (SQL NULL when missing or JSON null)
  def self.additional_text(*path)
    text_at(Message.arel_table[:additional_attributes], path)
  end

  def self.cast(expression, type)
    Arel::Nodes::NamedFunction.new('CAST', [expression.as(type)])
  end

  # Ruby's blank? of a JSON scalar: missing, null or an empty string
  def self.blank_text(text)
    Arel::Nodes::NamedFunction.new('NULLIF', [text, Arel::Nodes.build_quoted('')]).eq(nil)
  end

  def self.present_text(text)
    Arel::Nodes::NamedFunction.new('NULLIF', [text, Arel::Nodes.build_quoted('')]).not_eq(nil)
  end

  def self.text_at(jsonb, path)
    Arel::Nodes::InfixOperation.new('#>>', jsonb, Arel::Nodes.build_quoted("{#{path.join(',')}}"))
  end
  private_class_method :text_at
end
