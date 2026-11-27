# frozen_string_literal: true

module Monova
  module Core
    # DATA-03: a tenant-owned model's tenant_id is filled by the database
    # default from the tenancy helper, never assigned by the model, and
    # the model declares no default_scope: row-level security filters
    # rows and policies narrow them further.
    module TenantOwned
      extend ActiveSupport::Concern

      included do
        attr_readonly :tenant_id
      end
    end
  end
end
