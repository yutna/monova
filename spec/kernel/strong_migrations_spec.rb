# frozen_string_literal: true

require "rails_helper"

# DATA-05: core configures strong_migrations, so a dropped setting fails CI.
# rubocop:disable RSpec/DescribeClass -- a kernel spec proves the configured
# guard, not a class.
RSpec.describe "strong_migrations settings" do
  it "limits the lock timeout to 10 seconds" do
    expect(StrongMigrations.lock_timeout).to eq(10.seconds)
  end

  it "limits the statement timeout to one hour" do
    expect(StrongMigrations.statement_timeout).to eq(1.hour)
  end

  it "targets the pinned PostgreSQL major version" do
    expect(StrongMigrations.target_version).to eq(18)
  end

  it "checks a rollback" do
    expect(StrongMigrations.check_down).to be(true)
  end

  it "analyzes a table after adding an index" do
    expect(StrongMigrations.auto_analyze).to be(true)
  end

  it "alphabetizes the schema" do
    expect(StrongMigrations.alphabetize_schema).to be(true)
  end

  it "removes invalid indexes when a migration reruns" do
    expect(StrongMigrations.remove_invalid_indexes).to be(true)
  end
end
# rubocop:enable RSpec/DescribeClass
