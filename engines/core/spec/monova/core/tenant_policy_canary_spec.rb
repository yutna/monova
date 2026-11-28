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
# no policy and a table with neither, every policy the rule does not allow,
# and a view that reaches a tenant-owned table without security_invoker.
# The helpers must produce exactly the AUTH-09 policy. Every fixture is
# created as monova_migrator inside a transaction that rolls back, so
# nothing is left in the database (TS-07).
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
  let(:catalog) { TenantPolicyCatalog.new(migrator) }

  it "reports a table with tenant_id and no policy and a table with neither" do
    create_bad_tables

    expect_bad_tables_reported
  end

  it "applies the tenant_id column helper and the AUTH-09 policy" do
    create_policy_fixture
    expect_auth_09_policy
    expect_tenant_column
    expect { catalog.check! }.not_to raise_error
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

  it "reports an extra PUBLIC permissive policy on a tenant-owned table" do
    create_tenant_table(:data03_public_policy_probe)
    migrator.execute("CREATE POLICY data03_everyone ON data03_public_policy_probe FOR SELECT USING (true)")

    expect { catalog.check! }
      .to raise_error(TenantPolicyCatalog::Violation, /data03_public_policy_probe.*data03_everyone/)
  end

  it "reports a tenant policy whose expression differs from AUTH-09" do
    create_tenant_table(:data03_wrong_expression_probe)
    migrator.execute("ALTER POLICY tenant_isolation ON data03_wrong_expression_probe USING (true)")

    expect { catalog.check! }
      .to raise_error(TenantPolicyCatalog::Violation, /data03_wrong_expression_probe.*tenant_isolation/)
  end

  it "reports a monova_auth SELECT policy on a table outside the AUTH-07 exception" do
    create_tenant_table(:data03_auth_policy_probe)
    create_auth_policy(:data03_auth_policy_probe, :data03_auth_lookup)

    expect { catalog.check! }
      .to raise_error(TenantPolicyCatalog::Violation, /data03_auth_policy_probe.*data03_auth_lookup/)
  end

  it "accepts the one AUTH-07 SELECT policy on core_tokens" do
    create_auth_exception

    expect { TenantPolicyCatalog.new(migrator, schema: "data03_auth_exception").check! }
      .not_to raise_error
  end

  it "reports a view that reaches a tenant-owned table without security_invoker" do
    create_unsafe_views

    expect(catalog.violations).to include(
      a_string_including("public.data03_unsafe_view is not security_invoker"),
      a_string_including("public.data03_nested_view is not security_invoker")
    )
  end

  it "accepts a security_invoker view over a tenant-owned table" do
    create_safe_view

    expect { catalog.check! }.not_to raise_error
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
    violations = catalog.violations

    expect(violations).to contain_exactly(
      a_string_including("public.data03_tenant_probe has tenant_id without forced row-level security"),
      a_string_including("public.data03_tenant_probe has tenant_id without the AUTH-09 tenant policy"),
      a_string_including("public.data03_plain_probe has no tenant_id and is not a global table")
    )
    expect { catalog.check! }
      .to raise_error(TenantPolicyCatalog::Violation, /DATA-03/)
  end

  # Creates a tenant-owned table exactly as a migration would: the
  # tenant_id column helper plus add_tenant_policy.
  def create_tenant_table(table_name)
    migration = Class.new(ActiveRecord::Migration[8.1]) do
      define_method(:change) do
        create_table table_name do |t|
          t.tenant_id
        end
        add_tenant_policy table_name
      end
    end.new

    migration.exec_migration(migrator, :up)
  end

  def create_auth_policy(table_name, policy_name)
    migrator.execute(<<~SQL)
      CREATE POLICY #{policy_name} ON #{table_name}
        FOR SELECT TO monova_auth USING (true)
    SQL
  end

  # Creates core_tokens in its own schema so the AUTH-07 exception can be
  # proved without waiting for the migration that brings the real table.
  def create_auth_exception
    migrator.execute("CREATE SCHEMA data03_auth_exception")
    migrator.execute("SET LOCAL search_path TO data03_auth_exception, public")
    create_tenant_table(:core_tokens)
    create_auth_policy(:core_tokens, :data03_auth_lookup)
  end

  def create_unsafe_views
    create_tenant_table(:data03_view_probe)
    migrator.execute("CREATE VIEW data03_unsafe_view AS SELECT * FROM data03_view_probe")
    migrator.execute("CREATE VIEW data03_nested_view AS SELECT * FROM data03_unsafe_view")
  end

  def create_safe_view
    create_tenant_table(:data03_safe_view_probe)
    migrator.execute(<<~SQL)
      CREATE VIEW data03_safe_view WITH (security_invoker = true) AS
        SELECT * FROM data03_safe_view_probe
    SQL
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
