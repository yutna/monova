# frozen_string_literal: true

require "rails_helper"

# AUTH-09, AUTH-12 and TS-03: the helper sets the tenant for one
# transaction, never lets a transaction carry two tenants, and restores
# whatever the setting was when its block ends.
RSpec.describe Monova::Core::Tenancy do
  let(:connection) { ActiveRecord::Base.connection }
  let(:tenant_id) { "01932d6b-5c8a-7a2b-8c4d-0123456789ab" }
  let(:other_tenant_id) { "01932d6b-5c8a-7a2b-8c4d-0123456789cd" }

  def current_tenant
    connection.select_value("SELECT current_setting('app.tenant_id', true)")
  end

  def queries_while
    queries = []
    callback = ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def ignoring_invalid_tenant
    yield
  rescue Monova::Core::Tenancy::InvalidTenantId
    nil
  end

  def ignoring_statement_error
    yield
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def failing_query
    connection.execute("SELECT 1 / 0")
  end

  it "connects as the runtime role" do
    expect(connection.select_value("SELECT current_user")).to eq("monova_app")
  end

  it "sets the tenant inside the block" do
    inside = described_class.with_tenant(tenant_id) { current_tenant }

    expect(inside).to eq(tenant_id)
  end

  it "clears the tenant after the block" do
    described_class.with_tenant(tenant_id) { nil }

    expect(current_tenant).to be_blank
  end

  it "propagates an error from the block" do
    expect { described_class.with_tenant(tenant_id) { failing_query } }
      .to raise_error(ActiveRecord::StatementInvalid, /division by zero/)
  end

  it "clears the tenant after a block that raised" do
    ignoring_statement_error { described_class.with_tenant(tenant_id) { failing_query } }

    expect(current_tenant).to be_blank
  end

  it "refuses a nested call with another tenant" do
    expect do
      described_class.with_tenant(tenant_id) do
        described_class.with_tenant(other_tenant_id) { nil }
      end
    end.to raise_error(described_class::TenantConflict)
  end

  it "raises for a nil tenant" do
    expect { described_class.with_tenant(nil) { nil } }
      .to raise_error(described_class::InvalidTenantId)
  end

  it "raises for a blank tenant" do
    expect { described_class.with_tenant("   ") { nil } }
      .to raise_error(described_class::InvalidTenantId)
  end

  it "raises for a non-UUID tenant" do
    expect { described_class.with_tenant("not-a-uuid") { nil } }
      .to raise_error(described_class::InvalidTenantId)
  end

  it "does not touch the database for a non-UUID tenant" do
    queries = queries_while do
      ignoring_invalid_tenant { described_class.with_tenant("not-a-uuid") { nil } }
    end

    expect(queries).to be_empty
  end
end
