# frozen_string_literal: true

# DATA-05: a migration runs while the old code still serves requests, so
# strong_migrations stops an operation that would block reads or writes.
StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.statement_timeout = 1.hour
StrongMigrations.target_version = 18
StrongMigrations.check_down = true
StrongMigrations.auto_analyze = true
StrongMigrations.alphabetize_schema = true
StrongMigrations.remove_invalid_indexes = true
