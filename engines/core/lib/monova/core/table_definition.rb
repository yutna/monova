# frozen_string_literal: true

module Monova
  module Core
    # DATA-03 and AUTH-09: a tenant-owned table states its tenant_id
    # column in one line. The column is a UUID that the database fills
    # from the transaction's tenant setting, so an insert through the
    # tenancy helper needs no value; it references core_tenants and
    # starts an index.
    module TableDefinition
      TENANT_COLUMN_DEFAULT = -> { "NULLIF(current_setting('app.tenant_id', true), '')::uuid" }

      def tenant_id(**options)
        column :tenant_id, :uuid, null: false, default: TENANT_COLUMN_DEFAULT, **options
        index :tenant_id
        foreign_key :core_tenants, column: :tenant_id
      end
    end
  end
end
