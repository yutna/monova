# frozen_string_literal: true

# The irreversible fixture for script/ci/migration_replay_check: the up
# applies, but the down always fails, so the rollback check must report
# DATA-05.
class CreateMigrationReplayCanary < ActiveRecord::Migration[8.1]
  def up
    create_table :migration_replay_canary do |t|
      t.timestamps
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "the fixture has no down"
  end
end
