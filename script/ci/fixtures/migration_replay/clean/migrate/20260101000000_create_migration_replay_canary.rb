# frozen_string_literal: true

# The clean fixture for script/ci/migration_replay_check: a safe migration
# whose dump must match the expected structure file exactly.
class CreateMigrationReplayCanary < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_replay_canary do |t|
      t.timestamps
    end
  end
end
