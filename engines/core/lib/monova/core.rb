# frozen_string_literal: true

module Monova
  module Core
    # ARCH-07: core's tables start with the engine's name, core_, not with
    # the full namespace.
    def self.table_name_prefix
      "core_"
    end
  end
end

require "monova/core/engine"
require "monova/core/migration"
require "monova/core/table_definition"
