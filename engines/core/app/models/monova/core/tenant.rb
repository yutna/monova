# frozen_string_literal: true

module Monova
  module Core
    # AUTH-07: core_tenants is one of the two global tables. It holds a
    # tenant's identity, never tenant data, and only core maps it.
    class Tenant < ApplicationRecord
      validates :name, presence: true
    end
  end
end
