# frozen_string_literal: true

module Monova
  module Core
    class Engine < ::Rails::Engine
      isolate_namespace Monova::Core

      # ARCH-07: the engine's migrations run from its own db/migrate
      # through the application's db: tasks. They are never copied into
      # the root db/migrate.
      initializer "monova.core.migrations" do |app|
        paths = app.config.paths["db/migrate"]

        config.paths["db/migrate"].expanded.each do |path|
          paths << path unless paths.include?(path)
        end
      end
    end
  end
end
