# Automato fork: hooks the agents layer (automato_agents/) into Chatwoot's AsyncDispatcher.
# This must run before the to_prepare block in config/initializers/event_handlers.rb, which
# builds the Dispatcher and subscribes the listeners (BaseDispatcher#load_listeners).
# Initializers load in alphabetical order, so this block is registered first.
Rails.application.config.to_prepare do
  AsyncDispatcher.prepend(AutomatoAgents::AsyncDispatcherExtension)
end
