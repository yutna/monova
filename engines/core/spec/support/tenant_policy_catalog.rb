# frozen_string_literal: true

# DATA-03: every table in the primary database's public schema is either
# tenant-owned and carries a forced AUTH-09 policy and no other policy, or
# one of the two global tables or a Rails internal table. Every view either
# runs with the caller's rights or reads no tenant-owned table. A kernel
# spec and its canary read the catalog through this check, so a wrong query
# path cannot pass by inspecting nothing.
class TenantPolicyCatalog
  RULE_ID = "DATA-03"

  # The AUTH-09 expression as PostgreSQL renders it in pg_policies for
  # both USING and WITH CHECK.
  POLICY_EXPRESSION =
    "(tenant_id = (NULLIF(current_setting('app.tenant_id'::text, true), ''::text))::uuid)"

  GLOBAL_TABLES = %w[ar_internal_metadata core_tenants core_users schema_migrations].freeze

  # AUTH-07: only the authentication role may read these two tables
  # without a tenant, through one extra SELECT policy.
  AUTH_LOOKUP_TABLES = %w[core_machine_clients core_tokens].freeze
  AUTH_ROLE = "monova_auth"

  # Raised when the check found no table, so an empty input fails.
  class EmptyCatalog < StandardError; end

  # Raised with a DATA-03 message when at least one table breaks the rule.
  class Violation < StandardError; end

  attr_reader :connection, :schema

  def initialize(connection, schema: "public")
    @connection = connection
    @schema = schema
  end

  # Returns one message per table or view that breaks DATA-03 and raises
  # when the schema holds no table at all.
  def violations
    tables = catalog_rows
    raise EmptyCatalog, "#{RULE_ID}: found no table in schema #{schema.inspect}" if tables.empty?

    table_violations(tables) + view_violations
  end

  # Raises a Violation whose message names DATA-03, so a spec failure
  # reports the rule the catalog broke.
  def check!
    found = violations
    return if found.empty?

    raise Violation, "#{RULE_ID}: #{found.join("; ")}"
  end

  private

  def table_violations(rows)
    policies = policies_by_table

    rows.flat_map do |row|
      tablename = row["tablename"]
      table = "#{schema}.#{tablename}"

      if row["has_tenant_id"]
        tenant_violations(table, tablename, row, policies.fetch(tablename, []))
      elsif !GLOBAL_TABLES.include?(tablename)
        "#{table} has no tenant_id and is not a global table"
      end
    end.compact
  end

  def tenant_violations(table, tablename, row, table_policies)
    messages = []
    messages << "#{table} has tenant_id without forced row-level security" unless forced?(row)

    tenant_policies = table_policies.select { |policy| tenant_policy?(policy) }
    allowed = tenant_policies.dup
    auth_policies = table_policies.select { |policy| auth_select_policy?(policy) }
    allowed << auth_policies.first if AUTH_LOOKUP_TABLES.include?(tablename) && auth_policies.one?

    messages << "#{table} has tenant_id without the AUTH-09 tenant policy" if tenant_policies.empty?

    table_policies.each do |policy|
      next if allowed.include?(policy)

      messages << "#{table} has policy #{policy["policyname"]} that #{RULE_ID} does not allow"
    end

    messages
  end

  def forced?(row)
    row["relrowsecurity"] && row["relforcerowsecurity"]
  end

  # The only policy a tenant-owned table may carry for AUTH-09: the one
  # add_tenant_policy creates, permissive, for every command, applying to
  # PUBLIC, with both expressions the AUTH-09 expression.
  def tenant_policy?(policy)
    policy["permissive"] == "PERMISSIVE" &&
      policy["command"] == "ALL" &&
      policy["applies_to_public"] &&
      policy["using_expression"] == POLICY_EXPRESSION &&
      policy["check_expression"] == POLICY_EXPRESSION
  end

  # AUTH-07's one exception: a SELECT policy for the authentication role
  # alone. Whether it is permissive or restrictive is left to the issue
  # that creates it; neither can widen access beyond that role.
  def auth_select_policy?(policy)
    policy["command"] == "SELECT" && policy["applies_to_auth_only"]
  end

  def view_violations
    view_rows.filter_map do |row|
      next if row["security_invoker"]
      next unless row["reads_tenant_table"]

      "#{schema}.#{row["viewname"]} is not security_invoker and reads a tenant-owned table"
    end
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
             ) AS has_tenant_id
      FROM pg_tables t
      JOIN pg_class c ON c.relname = t.tablename
      JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = t.schemaname
      WHERE t.schemaname = #{connection.quote(schema)}
      ORDER BY t.tablename
    SQL
  end

  # Reads every policy with the fields DATA-03 compares. Roles are reduced
  # to the two shapes the rule allows: exactly PUBLIC and exactly the
  # authentication role.
  def policies_by_table
    connection.select_all(<<~SQL).to_a.group_by { |row| row["tablename"] }
      SELECT table_class.relname AS tablename,
             policy.polname AS policyname,
             CASE WHEN policy.polpermissive THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END AS permissive,
             CASE policy.polcmd
               WHEN '*' THEN 'ALL'
               WHEN 'r' THEN 'SELECT'
               WHEN 'a' THEN 'INSERT'
               WHEN 'w' THEN 'UPDATE'
               WHEN 'd' THEN 'DELETE'
             END AS command,
             pg_get_expr(policy.polqual, policy.polrelid) AS using_expression,
             pg_get_expr(policy.polwithcheck, policy.polrelid) AS check_expression,
             policy.polroles = '{0}'::oid[] AS applies_to_public,
             policy.polroles =
               ARRAY[(SELECT oid FROM pg_roles WHERE rolname = #{connection.quote(AUTH_ROLE)})]::oid[]
               AS applies_to_auth_only
      FROM pg_policy policy
      JOIN pg_class table_class ON table_class.oid = policy.polrelid
      JOIN pg_namespace rel_namespace ON rel_namespace.oid = table_class.relnamespace
      WHERE rel_namespace.nspname = #{connection.quote(schema)}
      ORDER BY table_class.relname, policy.polname
    SQL
  end

  # A view without security_invoker runs as its owner, so any tenant-owned
  # table it reaches, directly or through another view, is readable across
  # tenants when that owner has BYPASSRLS.
  def view_rows
    connection.select_all(<<~SQL).to_a
      WITH RECURSIVE view_references(view_oid, referenced_oid) AS (
        SELECT DISTINCT rewrite.ev_class, ref_dependency.refobjid
        FROM pg_rewrite rewrite
        JOIN pg_depend ref_dependency ON ref_dependency.objid = rewrite.oid
          AND ref_dependency.classid = 'pg_rewrite'::regclass
          AND ref_dependency.refclassid = 'pg_class'::regclass
        WHERE ref_dependency.refobjid <> rewrite.ev_class
        UNION
        SELECT view_references.view_oid, ref_dependency.refobjid
        FROM view_references
        JOIN pg_rewrite rewrite ON rewrite.ev_class = view_references.referenced_oid
        JOIN pg_depend ref_dependency ON ref_dependency.objid = rewrite.oid
          AND ref_dependency.classid = 'pg_rewrite'::regclass
          AND ref_dependency.refclassid = 'pg_class'::regclass
        WHERE ref_dependency.refobjid <> view_references.view_oid
      )
      SELECT catalog_view.relname AS viewname,
             coalesce('security_invoker=true' = ANY(catalog_view.reloptions), false) AS security_invoker,
             EXISTS (
               SELECT 1
               FROM view_references
               JOIN pg_class referenced_class ON referenced_class.oid = view_references.referenced_oid
               JOIN pg_namespace referenced_namespace ON referenced_namespace.oid = referenced_class.relnamespace
               WHERE view_references.view_oid = catalog_view.oid
                 AND referenced_namespace.nspname = #{connection.quote(schema)}
                 AND EXISTS (
                   SELECT 1
                   FROM information_schema.columns referenced_column
                   WHERE referenced_column.table_schema = referenced_namespace.nspname
                     AND referenced_column.table_name = referenced_class.relname
                     AND referenced_column.column_name = 'tenant_id'
                 )
             ) AS reads_tenant_table
      FROM pg_class catalog_view
      JOIN pg_namespace view_namespace ON view_namespace.oid = catalog_view.relnamespace
      WHERE catalog_view.relkind = 'v'
        AND view_namespace.nspname = #{connection.quote(schema)}
      ORDER BY catalog_view.relname
    SQL
  end
end
