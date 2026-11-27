# frozen_string_literal: true

# DATA-05 fixture: a table the canary's unsafe migration indexes.
class CreateStrongMigrationsCanary < ActiveRecord::Migration[8.1]
  def change
    create_table :strong_migrations_canary, id: :uuid do |t|
      t.timestamps
    end
  end
end
