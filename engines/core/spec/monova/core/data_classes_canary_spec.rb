# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/data_classes_catalog"

module DataClassesCanary
  # A second pool, connected as the migrator role: monova_app owns nothing
  # and cannot create the fixture tables (DATA-01).
  class Record < ActiveRecord::Base
    self.abstract_class = true
  end

  SCHEMA = "data11_canary"
end

# DATA-11 canary: the catalog check must reject a column with no class, a
# listed column that does not exist, a class outside the five, a table no
# engine claims, and a file that lists another engine's table. Every fixture
# is created as monova_migrator inside a transaction that rolls back, so
# nothing is left in the database (TS-07).
# rubocop:disable RSpec/DescribeClass -- a canary proves the check, not a
# class.
RSpec.describe "DATA-11 data classes canary" do
  around do |example|
    DataClassesCanary::Record.establish_connection(connection_config)
    migrator.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  ensure
    DataClassesCanary::Record.connection_pool.disconnect!
  end

  let(:migrator) { DataClassesCanary::Record.connection }

  it "reports a column with no data class" do
    create_table("core_data11_unclassified", "id uuid PRIMARY KEY DEFAULT uuidv7(), note text")

    expect_violation(/core_data11_unclassified\.note has no data class/) do
      check("core_data11_unclassified" => { "id" => "internal" })
    end
  end

  it "reports a listed column that does not exist" do
    create_table("core_data11_missing_column", "id uuid PRIMARY KEY DEFAULT uuidv7()")

    expect_violation(/core_data11_missing_column\.ghost is listed .* but does not exist/) do
      check("core_data11_missing_column" => { "id" => "internal", "ghost" => "internal" })
    end
  end

  it "reports a class that is not one of the five" do
    create_table("core_data11_bad_class", "id uuid PRIMARY KEY DEFAULT uuidv7()")

    expect_violation(/core_data11_bad_class\.id has class "confidential"/) do
      check("core_data11_bad_class" => { "id" => "confidential" })
    end
  end

  it "reports a table no engine claims" do
    create_table("data11_unclaimed", "id uuid PRIMARY KEY DEFAULT uuidv7()")

    expect_violation(/data11_unclaimed is not claimed by any engine/) { check }
  end

  it "reports a file that lists another engine's table" do
    create_table("billing_data11_probe", "id uuid PRIMARY KEY DEFAULT uuidv7()")

    expect_violation(/lists billing_data11_probe, which the core engine does not own/) do
      check("billing_data11_probe" => { "id" => "internal" })
    end
  end

  it "fails when the schema holds no table at all" do
    migrator.execute("CREATE SCHEMA data11_empty")

    expect { DataClassesCatalog.new(migrator, schema: "data11_empty", definitions: {}).check! }
      .to raise_error(DataClassesCatalog::EmptyCatalog, /DATA-11/)
  end

  def connection_config
    ActiveRecord::Base.connection_db_config.configuration_hash.merge(
      username: "monova_migrator",
      password: ENV.fetch("MONOVA_MIGRATOR_PASSWORD", "monova_migrator")
    )
  end

  def create_canary_schema
    migrator.execute("CREATE SCHEMA #{DataClassesCanary::SCHEMA}")
  end

  def create_table(table_name, columns)
    create_canary_schema
    migrator.execute("CREATE TABLE #{DataClassesCanary::SCHEMA}.#{table_name} (#{columns})")
  end

  def check(tables = {})
    catalog = DataClassesCatalog.new(
      migrator,
      schema: DataClassesCanary::SCHEMA,
      definitions: { "core" => tables }
    )
    catalog.check!
  end

  def expect_violation(pattern, &block)
    expect { block.call }.to raise_error(DataClassesCatalog::Violation, pattern)
  end
end
# rubocop:enable RSpec/DescribeClass
