# frozen_string_literal: true

# The unsafe fixture for script/ci/migration_replay_check: the first
# migration creates the table, and the second runs an operation
# strong_migrations rejects, so the replay must report DATA-05.
class CreateMigrationReplayCanary < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_replay_canary do |t|
      t.timestamps
    end
  end
end
