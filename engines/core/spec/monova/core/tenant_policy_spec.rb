# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/tenant_policy_catalog"

# DATA-03: every table in the primary database is either tenant-owned and
# carries a forced AUTH-09 policy and no other policy, or a global table or
# a Rails internal table. Every view either runs with the caller's rights
# or reads no tenant-owned table. The check reads PostgreSQL's catalog, so
# a table a migration created without its policy, or with an extra policy,
# fails the suite. Run the spec with `DB_ROLE=monova_migrator` to see the
# catalog from the owner's side.
# rubocop:disable RSpec/DescribeClass -- a kernel spec proves the catalog,
# not a class.
RSpec.describe "DATA-03 tenant policies" do
  let(:catalog) { TenantPolicyCatalog.new(ActiveRecord::Base.connection) }

  it "connects as the runtime role" do
    expect(ActiveRecord::Base.connection.select_value("SELECT current_user")).to eq("monova_app")
  end

  it "reads tables from the catalog" do
    expect(catalog.violations).to be_an(Array)
  end

  it "gives every table a forced AUTH-09 policy or a global exemption" do
    expect { catalog.check! }.not_to raise_error
  end
end
# rubocop:enable RSpec/DescribeClass
