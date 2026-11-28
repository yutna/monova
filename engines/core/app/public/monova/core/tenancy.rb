# frozen_string_literal: true

module Monova
  module Core
    # AUTH-09, AUTH-12 and TS-03: every tenant-owned query runs inside a
    # transaction whose `app.tenant_id` is set, the setting ends with the
    # transaction, and one real database transaction never carries two
    # tenants.
    module Tenancy
      # Raised before any query when the tenant ID cannot be a UUID.
      class InvalidTenantId < ArgumentError; end

      # Raised when the open transaction already works for another tenant.
      class TenantConflict < StandardError; end

      SETTING = "app.tenant_id"

      UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      # The tenant each real database transaction has used, keyed by that
      # transaction. Rails keeps one real transaction object for the whole
      # outermost transaction, even when it restarts the PostgreSQL
      # transaction after a nested rollback, so this record survives a
      # savepoint rollback and cannot reach the next transaction. The
      # transaction's own commit and rollback callbacks delete the entry.
      USED_TENANTS = {}
      USED_TENANTS_LOCK = Mutex.new

      class << self
        # Opens a transaction, sets the tenant for it, and yields. The block
        # returns its own value. Inside an already-open transaction it opens a
        # savepoint, and it restores the previous setting when its block ends:
        # a transaction-local setting lasts until the outermost transaction
        # ends, so the enclosing transaction would otherwise keep the tenant
        # (TS-03).
        #
        # It also remembers the tenant on the real database transaction at the
        # bottom of the open nesting, whatever its `joinable` flag and however
        # many savepoints sit above it. A later call in that transaction for
        # another tenant raises TenantConflict (AUTH-12), including after a
        # savepoint that used the first tenant rolled back.
        def with_tenant(tenant_id)
          id = tenant_id!(tenant_id)
          connection = ActiveRecord::Base.connection

          if connection.transaction_open?
            in_open_transaction(connection, id) { yield }
          else
            in_new_transaction(connection, id) { yield }
          end
        end

        private

        # The caller already owns the transaction. Check it before opening the
        # savepoint, so a refused call runs no part of its block.
        def in_open_transaction(connection, id)
          previous = current_setting(connection)
          raise TenantConflict, conflict_message(previous) if previous.present? && previous != id

          remember(connection, id)
          changed = previous.blank?

          begin
            connection.transaction(requires_new: true) do
              set_setting(connection, SETTING, id) if changed
              yield
            end
          ensure
            set_setting(connection, SETTING, previous.to_s) if changed && connection.transaction_open?
          end
        end

        # No transaction is open, so this call owns the real transaction. Its
        # setting ends with the commit, and its callbacks clear the record.
        def in_new_transaction(connection, id)
          connection.transaction do
            remember(connection, id)
            set_setting(connection, SETTING, id)
            yield
          end
        end

        def remember(connection, id)
          transaction = outermost_transaction(connection)

          USED_TENANTS_LOCK.synchronize do
            used = USED_TENANTS[transaction]
            raise TenantConflict, conflict_message(used) if used && used != id
            return if used

            USED_TENANTS[transaction] = id
          end

          forget = -> { forget(transaction) }
          transaction.after_commit(&forget)
          transaction.after_rollback(&forget)
        end

        def forget(transaction)
          USED_TENANTS_LOCK.synchronize { USED_TENANTS.delete(transaction) }
        end

        def conflict_message(tenant_id)
          "the transaction already works for tenant #{tenant_id}"
        end

        # Rails exposes the current transaction as the innermost one, which is
        # a savepoint when the caller is nested, and has no public reader for
        # the real transaction below it. The callbacks must sit on that real
        # transaction: a savepoint under a non-joinable transaction runs its
        # own callbacks when it commits, which would forget the record before
        # the transaction ends.
        def outermost_transaction(connection)
          connection.transaction_manager.instance_variable_get(:@stack).first
        end

        def current_setting(connection)
          connection.exec_query("SELECT current_setting('#{SETTING}', true)").rows.first.first
        end

        def tenant_id!(tenant_id)
          id = tenant_id.to_s.downcase
          return id if UUID_FORMAT.match?(id)

          raise InvalidTenantId, "tenant_id must be a UUID"
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
