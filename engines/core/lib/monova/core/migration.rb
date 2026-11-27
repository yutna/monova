# frozen_string_literal: true

module Monova
  module Core
    # DATA-08: every table's primary key is a UUIDv7 that the database
    # fills. Prepended to ActiveRecord::Migration, so a migration calls
    # create_table with no id option and never falls back to bigint or
    # to a random version 4 UUID.
    module Migration
      UUID_V7_DEFAULT = -> { "uuidv7()" }

      # AUTH-09: a row is visible and writable only when its tenant_id
      # matches the transaction's tenant setting. With no tenant set the
      # comparison is NULL, so no row matches.
      TENANT_POLICY_NAME = "tenant_isolation"
      TENANT_POLICY_EXPRESSION =
        "tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid"

      def create_table(table_name, id: :uuid, default: nil, **options, &block)
        default = UUID_V7_DEFAULT if default.nil? && id == :uuid

        super(table_name, id: id, default: default, **options, &block)
      end

      # DATA-03: a tenant-owned table enables and forces row-level
      # security and carries one policy whose USING and WITH CHECK are
      # the AUTH-09 expression. Reversible, so a rolled-back migration
      # removes them again.
      def add_tenant_policy(table_name)
        table = quote_table_name(table_name)
        policy = quote_table_name(TENANT_POLICY_NAME)

        # DATA-05: row-level security and a policy are catalog changes on
        # the table this migration just created, so they take a brief
        # lock, rewrite nothing and are safe to run with the old code
        # still serving requests.
        reversible do |direction|
          direction.up do
            safety_assured do
              execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
              execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
              execute <<~SQL
                CREATE POLICY #{policy} ON #{table}
                  FOR ALL
                  USING (#{TENANT_POLICY_EXPRESSION})
                  WITH CHECK (#{TENANT_POLICY_EXPRESSION})
              SQL
            end
          end

          direction.down do
            safety_assured do
              execute "DROP POLICY #{policy} ON #{table}"
              execute "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
              execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
            end
          end
        end
      end
    end
  end
end
