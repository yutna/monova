# frozen_string_literal: true

require "rails_helper"

module TenantOwnedProbe
  # A model with no table: it proves only what the concern declares.
  class Record < ActiveRecord::Base
    self.abstract_class = true
    include Monova::Core::TenantOwned
  end
end

# DATA-03: a tenant-owned model marks tenant_id read-only and declares no
# default_scope. Row-level security filters rows, so a default_scope would
# hide a policy failure behind application code.
RSpec.describe Monova::Core::TenantOwned do
  let(:model) { TenantOwnedProbe::Record }

  it "marks tenant_id read-only" do
    expect(model.readonly_attributes).to include("tenant_id")
  end

  it "declares no default_scope" do
    expect(model.default_scopes).to be_empty
  end
end
