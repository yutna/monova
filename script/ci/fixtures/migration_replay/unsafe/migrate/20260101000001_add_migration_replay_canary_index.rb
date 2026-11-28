# frozen_string_literal: true

# The unsafe fixture for script/ci/migration_replay_check: adding the index
# without `algorithm: :concurrently` blocks writes, so strong_migrations
# must reject it (DATA-05).
class AddMigrationReplayCanaryIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :migration_replay_canary, :created_at
  end
end
