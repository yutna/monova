# frozen_string_literal: true

module Monova
  module Core
    # DATA-08: every table's primary key is a UUIDv7 that the database
    # fills. Prepended to ActiveRecord::Migration, so a migration calls
    # create_table with no id option and never falls back to bigint or
    # to a random version 4 UUID.
    module Migration
      UUID_V7_DEFAULT = -> { "uuidv7()" }

      def create_table(table_name, id: :uuid, default: nil, **options, &block)
        default = UUID_V7_DEFAULT if default.nil? && id == :uuid

        super(table_name, id: id, default: default, **options, &block)
      end
    end
  end
end
