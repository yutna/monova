# frozen_string_literal: true

require "rails_helper"

# AUTH-05, AUTH-07, AUTH-09, DATA-03, DATA-07: a membership belongs to one
# tenant and one user. Row-level security keeps it in its tenant, the unique
# index keeps one membership per user and tenant, and the check constraints
# keep the role and status to the values the model validates.
RSpec.describe Monova::Core::Membership do
  let(:tenant) { Monova::Core::Tenant.create!(name: "Acme") }
  let(:other_tenant) { Monova::Core::Tenant.create!(name: "Other") }
  let(:user) { create(:core_user) }
  let(:attributes) { { user: user, role: "member", status: "active" } }

  def create_in(tenant_id, values = attributes)
    Monova::Core::Tenancy.with_tenant(tenant_id) { described_class.create!(values) }
  end

  def build_in(tenant_id, values = attributes)
    Monova::Core::Tenancy.with_tenant(tenant_id) do
      membership = described_class.new(values)
      membership.valid?
      membership
    end
  end

  it "connects as the runtime role" do
    expect(described_class.connection.select_value("SELECT current_user")).to eq("monova_app")
  end

  it "fills tenant_id from the transaction's tenant" do
    membership = create_in(tenant.id)

    reloaded = Monova::Core::Tenancy.with_tenant(tenant.id) { membership.reload }

    expect(reloaded.tenant_id).to eq(tenant.id)
  end

  it "is invisible inside another tenant" do
    membership = create_in(tenant.id)

    found = Monova::Core::Tenancy.with_tenant(other_tenant.id) do
      described_class.find_by(id: membership.id)
    end

    expect(found).to be_nil
  end

  it "is invisible without a tenant" do
    membership = create_in(tenant.id)

    expect(described_class.find_by(id: membership.id)).to be_nil
  end

  it "refuses tenant B's ID inside tenant A's transaction" do
    membership = described_class.new(attributes.merge(tenant_id: other_tenant.id))

    expect do
      Monova::Core::Tenancy.with_tenant(tenant.id) { membership.save! }
    end.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
  end

  it "refuses a second membership for the same user and tenant at the database" do
    create_in(tenant.id)
    duplicate = described_class.new(attributes)

    expect do
      Monova::Core::Tenancy.with_tenant(tenant.id) { duplicate.save!(validate: false) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "refuses an unknown role at the database" do
    membership = described_class.new(attributes.merge(role: "superuser"))

    expect do
      Monova::Core::Tenancy.with_tenant(tenant.id) { membership.save!(validate: false) }
    end.to raise_error(ActiveRecord::StatementInvalid, /core_memberships_role_allowed/)
  end

  it "rejects a role outside the configured roles" do
    membership = build_in(tenant.id, attributes.merge(role: "superuser"))

    expect(membership.errors[:role]).to include("is not included in the list")
  end

  it "rejects a status outside active and suspended" do
    membership = build_in(tenant.id, attributes.merge(status: "deleted"))

    expect(membership.errors[:status]).to include("is not included in the list")
  end

  it "reports a repeated user in the same tenant on the user field" do
    create_in(tenant.id)
    duplicate = build_in(tenant.id, attributes.merge(tenant_id: tenant.id))

    expect(duplicate.errors[:user_id]).to include("has already been taken")
  end
end
