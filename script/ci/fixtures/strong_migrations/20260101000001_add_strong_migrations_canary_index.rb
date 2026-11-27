# frozen_string_literal: true

# DATA-05 fixture: one known unsafe operation. Adding the index without
# `algorithm: :concurrently` blocks writes on a table the application uses.
class AddStrongMigrationsCanaryIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :strong_migrations_canary, :created_at
  end
end
