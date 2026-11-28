# frozen_string_literal: true

# The rollback fixture for script/ci/migration_replay_check: `up` adds an
# index, `down` has no step for it, so rolling this migration back leaves the
# index behind and the check must report DATA-05 naming the migration and the
# index.
class AddMigrationReplayLeftoverIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    reversible do |direction|
      direction.up do
        add_index :migration_replay_canary, :created_at,
          name: "migration_replay_leftover_index", algorithm: :concurrently
      end
    end
  end
end
