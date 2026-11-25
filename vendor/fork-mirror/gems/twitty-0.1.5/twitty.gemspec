# -*- encoding: utf-8 -*-
# stub: twitty 0.1.5 ruby lib

Gem::Specification.new do |s|
  s.name = "twitty".freeze
  s.version = "0.1.5".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/chatwoot/twitty/issues", "homepage_uri" => "https://github.com/chatwoot/twitty", "rubygems_mfa_required" => "false", "source_code_uri" => "https://github.com/chatwoot/twitty" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Subin T P".freeze, "Pranav Raj S".freeze, "Sojan Jose".freeze]
  s.bindir = "exe".freeze
  s.date = "2023-03-15"
  s.description = "Twitty makes working with the twitter account subscriptions APIs much easier".freeze
  s.email = ["hello@thoughtwoot.com".freeze, "subin@thoughtwoot.com".freeze, "pranav@thoughtwoot.com".freeze, "sojan@thoughtwoot.com".freeze]
  s.files = [".circleci/config.yml".freeze, ".github/workflows/gempush.yml".freeze, ".gitignore".freeze, ".rspec".freeze, ".rubocop.yml".freeze, ".rubocop_todo.yml".freeze, ".ruby-version".freeze, ".travis.yml".freeze, "CODE_OF_CONDUCT.md".freeze, "Gemfile".freeze, "Gemfile.lock".freeze, "LICENSE.txt".freeze, "README.md".freeze, "Rakefile".freeze, "bin/console".freeze, "bin/setup".freeze, "lib/twitty.rb".freeze, "lib/twitty/config.rb".freeze, "lib/twitty/constants.rb".freeze, "lib/twitty/errors.rb".freeze, "lib/twitty/facade.rb".freeze, "lib/twitty/payload.rb".freeze, "lib/twitty/request.rb".freeze, "lib/twitty/response.rb".freeze, "lib/twitty/version.rb".freeze, "twitty.gemspec".freeze]
  s.homepage = "https://www.chatwoot.com".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.1.2".freeze
  s.summary = "Twitter API wrapper".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<bundler>.freeze, ["~> 2".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.0".freeze])
  s.add_runtime_dependency(%q<oauth>.freeze, [">= 0".freeze])
end

