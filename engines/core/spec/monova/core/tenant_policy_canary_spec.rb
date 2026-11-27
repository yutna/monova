# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/tenant_policy_catalog"

module TenantPolicyCanary
  # A second pool, connected as the migrator role: monova_app owns nothing
  # and cannot create the fixture tables (DATA-01).
  class Record < ActiveRecord::Base
    self.abstract_class = true
  end

  # PostgreSQL's rendering of AUTH-09's expression, written out rather than
  # borrowed from the check, so a wrong expected text fails the canary.
  AUTH_09_POLICY =
    "(tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)"
end

# DATA-03 canary: the catalog check must reject a table with tenant_id and
# no policy and a table with neither, and the helpers must produce exactly
# the AUTH-09 policy. Every fixture is created as monova_migrator inside a
# transaction that rolls back, so nothing is left in the database (TS-07).
# rubocop:disable RSpec/DescribeClass -- a canary proves the guard catalog,
# not a class.
RSpec.describe "DATA-03 catalog check canary" do
  around do |example|
    TenantPolicyCanary::Record.establish_connection(connection_config)
    migrator.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  ensure
    TenantPolicyCanary::Record.connection_pool.disconnect!
  end

  let(:migrator) { TenantPolicyCanary::Record.connection }

  it "reports a table with tenant_id and no policy and a table with neither" do
    create_bad_tables

    expect_bad_tables_reported
  end

  it "applies the tenant_id column helper and the AUTH-09 policy" do
    create_policy_fixture
    expect_auth_09_policy
    expect_tenant_column
    expect { TenantPolicyCatalog.new(migrator).check! }.not_to raise_error
  end

  it "reverts the column and the policy" do
    migration = create_policy_fixture
    migration.exec_migration(migrator, :down)

    expect_reverted
  end

  it "fails when the catalog holds no table at all" do
    migrator.execute("CREATE SCHEMA data03_empty")

    expect { TenantPolicyCatalog.new(migrator, schema: "data03_empty").check! }
      .to raise_error(TenantPolicyCatalog::EmptyCatalog, /DATA-03/)
  end

  def connection_config
    ActiveRecord::Base.connection_db_config.configuration_hash.merge(
      username: "monova_migrator",
      password: ENV.fetch("MONOVA_MIGRATOR_PASSWORD", "monova_migrator")
    )
  end

  def create_bad_tables
    migrator.execute("CREATE TABLE data03_tenant_probe (id uuid PRIMARY KEY DEFAULT uuidv7(), tenant_id uuid NOT NULL)")
    migrator.execute("CREATE TABLE data03_plain_probe (id uuid PRIMARY KEY DEFAULT uuidv7())")
  end

  def expect_bad_tables_reported
    violations = TenantPolicyCatalog.new(migrator).violations

    expect(violations).to contain_exactly(
      a_string_including("public.data03_tenant_probe has tenant_id without forced row-level security"),
      a_string_including("public.data03_plain_probe has no tenant_id and is not a global table")
    )
    expect { TenantPolicyCatalog.new(migrator).check! }
      .to raise_error(TenantPolicyCatalog::Violation, /DATA-03/)
  end

  # Runs the helpers exactly as a migration would, through exec_migration
  # on the migrator connection.
  def create_policy_fixture
    migration = Class.new(ActiveRecord::Migration[8.1]) do
      def change
        create_table :data03_policy_probe do |t|
          t.tenant_id
        end
        add_tenant_policy :data03_policy_probe
      end
    end.new

    migration.exec_migration(migrator, :up)
    migration
  end

  def expect_auth_09_policy
    policy = migrator.select_one(<<~SQL)
      SELECT qual, with_check
      FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'data03_policy_probe'
    SQL
    security = migrator.select_one(<<~SQL)
      SELECT relrowsecurity, relforcerowsecurity
      FROM pg_class
      WHERE oid = 'public.data03_policy_probe'::regclass
    SQL

    expect(policy.values_at("qual", "with_check")).to eq(
      [ TenantPolicyCanary::AUTH_09_POLICY, TenantPolicyCanary::AUTH_09_POLICY ]
    )
    expect(security.values_at("relrowsecurity", "relforcerowsecurity")).to eq([ true, true ])
  end

  def expect_tenant_column
    column = migrator.select_one(<<~SQL)
      SELECT data_type, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'data03_policy_probe'
        AND column_name = 'tenant_id'
    SQL
    foreign_key = migrator.select_value(<<~SQL)
      SELECT confrelid::regclass::text
      FROM pg_constraint
      WHERE conrelid = 'public.data03_policy_probe'::regclass AND contype = 'f'
    SQL
    index = migrator.select_value(<<~SQL)
      SELECT indexdef
      FROM pg_indexes
      WHERE schemaname = 'public' AND tablename = 'data03_policy_probe'
        AND indexdef LIKE '%(tenant_id)%'
    SQL

    expect(column.values_at("data_type", "is_nullable", "column_default")).to eq(
      [ "uuid", "NO", "(NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid" ]
    )
    expect(foreign_key).to eq("core_tenants")
    expect(index).to include("(tenant_id)")
  end

  def expect_reverted
    expect(migrator.select_value("SELECT to_regclass('public.data03_policy_probe')::text")).to be_nil
    expect(migrator.select_value("SELECT count(*) FROM pg_policies WHERE tablename = 'data03_policy_probe'")).to eq(0)
  end
end
# rubocop:enable RSpec/DescribeClass
