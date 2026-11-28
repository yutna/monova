# frozen_string_literal: true

# The first migration of the later-leftover fixture for
# script/ci/migration_replay_check: it creates the table the next migration
# leaves behind a function after.
class CreateMigrationReplayCanary < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_replay_canary do |t|
      t.timestamps
    end
  end
end
