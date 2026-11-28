# frozen_string_literal: true

module Monova
  module Core
    # AUTH-09, AUTH-12 and TS-03: every tenant-owned query runs inside a
    # transaction whose `app.tenant_id` is set, the setting ends with the
    # transaction, and one transaction never carries two tenants.
    module Tenancy
      # Raised before any query when the tenant ID cannot be a UUID.
      class InvalidTenantId < ArgumentError; end

      # Raised when the open transaction already works for another tenant.
      class TenantConflict < StandardError; end

      SETTING = "app.tenant_id"

      UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      # The tenant each real transaction has used. Rails keeps the
      # transaction object on the connection's stack until the transaction
      # ends, and the weak key lets the entry go with it. A spec's fixture
      # transaction is not joinable, so it is not remembered.
      USED_TENANTS = ObjectSpace::WeakKeyMap.new

      class << self
        # Opens a transaction, sets the tenant for it, and yields. The block
        # returns its own value. Inside an already-open transaction it opens a
        # savepoint, and it restores the previous setting when its block ends:
        # a transaction-local setting lasts until the outermost transaction
        # ends, so the enclosing transaction would otherwise keep the tenant
        # (TS-03). A real enclosing transaction remembers the tenant it used,
        # so a later call in it with another tenant raises (AUTH-12).
        def with_tenant(tenant_id)
          id = tenant_id!(tenant_id)
          connection = ActiveRecord::Base.connection
          nested = connection.transaction_open?
          enclosing = connection.current_transaction
          real = nested && enclosing.joinable?
          used = USED_TENANTS[enclosing] if real
          previous = current_setting(connection) if nested

          if previous.present? && previous != id
            raise TenantConflict, "the transaction already works for tenant #{previous}"
          end
          if used.present? && used != id
            raise TenantConflict, "the transaction already works for tenant #{used}"
          end

          USED_TENANTS[enclosing] = id if real

          changed = previous.blank?

          begin
            connection.transaction(requires_new: nested) do
              set_setting(connection, id) if changed
              yield
            end
          ensure
            set_setting(connection, previous.to_s) if changed && connection.transaction_open?
          end
        end

        private

        def tenant_id!(tenant_id)
          id = tenant_id.to_s.downcase
          return id if UUID_FORMAT.match?(id)

          raise InvalidTenantId, "tenant_id must be a UUID"
        end

        def current_setting(connection)
          connection.select_value("SELECT current_setting('#{SETTING}', true)")
        end

        def set_setting(connection, value)
          connection.exec_query(
            "SELECT set_config('#{SETTING}', $1, true)",
            "Tenancy",
            [ ActiveRecord::Relation::QueryAttribute.new("tenant_id", value, ActiveRecord::Type::String.new) ]
          )
        end
      end
    end
  end
end
