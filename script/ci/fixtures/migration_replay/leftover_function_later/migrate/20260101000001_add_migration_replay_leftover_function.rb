# frozen_string_literal: true

# The rollback fixture for script/ci/migration_replay_check: this is the
# second migration, and `up` creates a function with no `down` step, so the
# function outlives both its own rollback and the earlier migration's rollback.
# The check must blame this migration, not the one before it.
class AddMigrationReplayLeftoverFunction < ActiveRecord::Migration[8.1]
  def change
    reversible do |direction|
      direction.up do
        # A function in this scratch fixture is safe; the canary exists to
        # prove the rollback check, not to model a production migration.
        safety_assured do
          execute <<~SQL
            CREATE FUNCTION migration_replay_later_no_down() RETURNS integer
              LANGUAGE sql
              AS 'SELECT 1';
          SQL
        end
      end
    end
  end
end
