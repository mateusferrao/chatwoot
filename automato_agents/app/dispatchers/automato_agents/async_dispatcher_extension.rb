# Prepended to AsyncDispatcher by config/initializers/automato_agents.rb, before
# config/initializers/event_handlers.rb subscribes the listeners.
module AutomatoAgents::AsyncDispatcherExtension
  def listeners
    super + [AutomatoAgents::EventListener.instance]
  end
end
