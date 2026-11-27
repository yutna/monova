# frozen_string_literal: true

module Monova
  module Core
    class Engine < ::Rails::Engine
      isolate_namespace Monova::Core
    end
  end
end
