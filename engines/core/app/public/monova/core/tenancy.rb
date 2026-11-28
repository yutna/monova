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

      # The tenant the enclosing real transaction has used. It is a
      # transaction-local setting like SETTING, so it lasts until that
      # transaction ends and a savepoint rollback reverts it. A spec's
      # non-joinable fixture transaction is not a real transaction and is
      # not remembered.
      USED_SETTING = "app.tenant_used"

      UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      class << self
        # Opens a transaction, sets the tenant for it, and yields. The block
        # returns its own value. Inside an already-open transaction it opens a
        # savepoint, and it restores the previous setting when its block ends:
        # a transaction-local setting lasts until the outermost transaction
        # ends, so the enclosing transaction would otherwise keep the tenant
        # (TS-03). A joinable enclosing transaction also records its tenant in
        # USED_SETTING, so a later call at any savepoint depth raises for a
        # different tenant (AUTH-12); the record is cleared when that
        # transaction ends.
        def with_tenant(tenant_id)
          id = tenant_id!(tenant_id)
          connection = ActiveRecord::Base.connection
          nested = connection.transaction_open?
          enclosing = connection.current_transaction
          real = nested && enclosing.joinable?
          previous, used = current_settings(connection) if nested

          if previous.present? && previous != id
            raise TenantConflict, "the transaction already works for tenant #{previous}"
          end
          if real && used.present? && used != id
            raise TenantConflict, "the transaction already works for tenant #{used}"
          end

          remember_tenant(connection, enclosing, id) if real && used.blank?

          changed = previous.blank?

          begin
            connection.transaction(requires_new: nested) do
              set_setting(connection, SETTING, id) if changed
              yield
            end
          ensure
            set_setting(connection, SETTING, previous.to_s) if changed && connection.transaction_open?
          end
        end

        private

        def tenant_id!(tenant_id)
          id = tenant_id.to_s.downcase
          return id if UUID_FORMAT.match?(id)

          raise InvalidTenantId, "tenant_id must be a UUID"
        end

        def current_settings(connection)
          connection.select_rows(
            "SELECT current_setting('#{SETTING}', true), current_setting('#{USED_SETTING}', true)"
          ).first
        end

        # The cleanup callbacks run when the enclosing savepoint or transaction
        # commits, which Rails propagates to the first real transaction, or
        # when it rolls back, which also reverts the setting. In a spec the
        # fixture transaction outlives the real one, so its setting has to be
        # cleared explicitly.
        def remember_tenant(connection, transaction, id)
          set_setting(connection, USED_SETTING, id)
          forget = -> { forget_tenant(connection) }
          transaction.user_transaction.after_commit(&forget)
          transaction.user_transaction.after_rollback(&forget)
        end

        def forget_tenant(connection)
          set_setting(connection, USED_SETTING, "") if connection.transaction_open?
        end

        def set_setting(connection, name, value)
          connection.exec_query(
            "SELECT set_config('#{name}', $1, true)",
            "Tenancy",
            [ ActiveRecord::Relation::QueryAttribute.new("tenant_id", value, ActiveRecord::Type::String.new) ]
          )
        end
      end
    end
  end
end
