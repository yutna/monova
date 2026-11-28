# frozen_string_literal: true

# The first migration of the leftover-index fixture for
# script/ci/migration_replay_check: it creates the table the next migration
# indexes.
class CreateMigrationReplayCanary < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_replay_canary do |t|
      t.timestamps
    end
  end
end
