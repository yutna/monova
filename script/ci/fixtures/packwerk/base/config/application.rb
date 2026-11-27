# frozen_string_literal: true

# A minimal Rails application for the Packwerk canary (TS-07). The canary
# copies this fixture to a temporary directory, adds one case's packages
# and runs bin/packwerk there.
require "rails"

module PackwerkCanary
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
    config.api_only = true
    config.autoload_paths += Dir[Rails.root.join("engines/*/app/models")]
    config.autoload_paths += Dir[Rails.root.join("engines/*/app/public")]
  end
end
