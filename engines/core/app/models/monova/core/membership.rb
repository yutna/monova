# frozen_string_literal: true

module Monova
  module Core
    # AUTH-05, AUTH-07, DATA-03, DATA-07: a membership is a user's role in
    # one tenant. Row-level security keeps it in its tenant, so the model
    # includes TenantOwned instead of naming a tenant; its validations mirror
    # the table's check constraints and its unique index.
    class Membership < ApplicationRecord
      include TenantOwned

      # AUTH-05: the roles are configuration in core, not rows a tenant edits.
      ROLES = %w[owner admin member].freeze
      STATUSES = %w[active suspended].freeze

      belongs_to :user

      validates :role, presence: true, inclusion: { in: ROLES }
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :user_id, uniqueness: { scope: :tenant_id }
    end
  end
end
