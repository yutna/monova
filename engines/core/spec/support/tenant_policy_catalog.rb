# frozen_string_literal: true

# DATA-03: every table in the primary database's public schema is either
# tenant-owned and carries a forced AUTH-09 policy, or one of the two
# global tables or a Rails internal table. A kernel spec and its canary
# read the catalog through this check, so a wrong query path cannot pass
# by inspecting nothing.
class TenantPolicyCatalog
  RULE_ID = "DATA-03"

  # The AUTH-09 expression as PostgreSQL renders it in pg_policies for
  # both USING and WITH CHECK.
  POLICY_EXPRESSION =
    "(tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)"

  GLOBAL_TABLES = %w[ar_internal_metadata core_tenants core_users schema_migrations].freeze

  # Raised when the check found no table, so an empty input fails.
  class EmptyCatalog < StandardError; end

  # Raised with a DATA-03 message when at least one table breaks the rule.
  class Violation < StandardError; end

  attr_reader :connection, :schema

  def initialize(connection, schema: "public")
    @connection = connection
    @schema = schema
  end

  # Returns one message per table that breaks DATA-03 and raises when the
  # schema holds no table at all.
  def violations
    rows = catalog_rows
    raise EmptyCatalog, "#{RULE_ID}: found no table in schema #{schema.inspect}" if rows.empty?

    rows.filter_map do |row|
      table = "#{schema}.#{row["tablename"]}"

      if row["has_tenant_id"]
        next if forced_policy?(row)

        "#{table} has tenant_id without forced row-level security and the AUTH-09 policy"
      elsif !GLOBAL_TABLES.include?(row["tablename"])
        "#{table} has no tenant_id and is not a global table"
      end
    end
  end

  # Raises a Violation whose message names DATA-03, so a spec failure
  # reports the rule the catalog broke.
  def check!
    found = violations
    return if found.empty?

    raise Violation, "#{RULE_ID}: #{found.join("; ")}"
  end

  private

  def forced_policy?(row)
    row["relrowsecurity"] && row["relforcerowsecurity"] && row["has_tenant_policy"]
  end

  def catalog_rows
    connection.select_all(<<~SQL).to_a
      SELECT t.tablename,
             c.relrowsecurity,
             c.relforcerowsecurity,
             EXISTS (
               SELECT 1
               FROM information_schema.columns col
               WHERE col.table_schema = t.schemaname
                 AND col.table_name = t.tablename
                 AND col.column_name = 'tenant_id'
             ) AS has_tenant_id,
             EXISTS (
               SELECT 1
               FROM pg_policies policy
               WHERE policy.schemaname = t.schemaname
                 AND policy.tablename = t.tablename
                 AND policy.qual = #{connection.quote(POLICY_EXPRESSION)}
                 AND policy.with_check = #{connection.quote(POLICY_EXPRESSION)}
             ) AS has_tenant_policy
      FROM pg_tables t
      JOIN pg_class c ON c.relname = t.tablename
      JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = t.schemaname
      WHERE t.schemaname = #{connection.quote(schema)}
      ORDER BY t.tablename
    SQL
  end
end
