# frozen_string_literal: true

# DATA-08: every create_table in a migration gets core's UUIDv7 table
# helper, so a new table never falls back to bigint or gen_random_uuid().
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migration.prepend(Monova::Core::Migration)
end

# DATA-10: datetime and timestamp columns keep their zone, so a
# `t.timestamps` becomes `timestamp with time zone`.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  self.datetime_type = :timestamptz
end
