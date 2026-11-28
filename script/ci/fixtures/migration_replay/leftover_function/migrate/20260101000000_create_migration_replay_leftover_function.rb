# frozen_string_literal: true

# The rollback fixture for script/ci/migration_replay_check: `up` creates a
# function, `down` only drops the table, so rolling back leaves the function
# behind and the check must report DATA-05 naming the migration and the
# function.
class CreateMigrationReplayLeftoverFunction < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_replay_canary do |t|
      t.timestamps
    end

    reversible do |direction|
      direction.up do
        # A function in this scratch fixture is safe; the canary exists to
        # prove the rollback check, not to model a production migration.
        safety_assured do
          execute <<~SQL
            CREATE FUNCTION migration_replay_no_down() RETURNS integer
              LANGUAGE sql
              AS 'SELECT 1';
          SQL
        end
      end
    end
  end
end
