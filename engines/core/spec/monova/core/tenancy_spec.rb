# frozen_string_literal: true

require "rails_helper"

# AUTH-09, AUTH-12 and TS-03: the helper sets the tenant for one
# transaction, never lets a real database transaction carry two tenants,
# and restores whatever the setting was when its block ends. The
# "without transactional fixtures" context runs without the fixture
# transaction, so every savepoint and commit there is PostgreSQL's own,
# as in the gate's probe.
RSpec.describe Monova::Core::Tenancy do
  let(:connection) { ActiveRecord::Base.connection }
  let(:tenant_id) { "01932d6b-5c8a-7a2b-8c4d-0123456789ab" }
  let(:other_tenant_id) { "01932d6b-5c8a-7a2b-8c4d-0123456789cd" }

  def current_tenant
    connection.exec_query("SELECT current_setting('app.tenant_id', true)").rows.first.first
  end

  def current_transaction_id
    connection.exec_query("SELECT pg_current_xact_id()::text").rows.first.first
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

  def tenants_seen_in_outer_transaction(*tenant_ids)
    seen = []
    ActiveRecord::Base.transaction do
      tenant_ids.each { |id| described_class.with_tenant(id) { seen << current_tenant } }
    end
    seen
  end

  def second_call_inside_savepoint(first_id, second_id)
    ActiveRecord::Base.transaction do
      described_class.with_tenant(first_id) { nil }
      ActiveRecord::Base.transaction(requires_new: true) do
        described_class.with_tenant(second_id) { nil }
      end
    end
  end

  def first_call_inside_savepoint(first_id, second_id)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.transaction(requires_new: true) do
        described_class.with_tenant(first_id) { nil }
      end
      described_class.with_tenant(second_id) { nil }
    end
  end

  def non_joinable_second_block
    ran = false
    raised = false

    begin
      ActiveRecord::Base.transaction(joinable: false) do
        described_class.with_tenant(tenant_id) { nil }
        described_class.with_tenant(other_tenant_id) { ran = true }
      end
    rescue described_class::TenantConflict
      raised = true
    end

    [ raised, ran ]
  end

  def savepoint_rollback_then_other_tenant
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.transaction(requires_new: true) do
        described_class.with_tenant(tenant_id) { nil }
        raise ActiveRecord::Rollback
      end
      described_class.with_tenant(other_tenant_id) { nil }
    end
  end

  def savepoint_inside_block_other_tenant
    described_class.with_tenant(tenant_id) do
      ActiveRecord::Base.transaction(requires_new: true) do
        described_class.with_tenant(other_tenant_id) { nil }
      end
    end
  end

  def tenants_seen_in_one_transaction(*tenant_ids)
    seen = []
    ActiveRecord::Base.transaction do
      tenant_ids.each { |id| described_class.with_tenant(id) { seen << [ current_transaction_id, id ] } }
    end
    seen
  end

  def tenants_seen_in_separate_transactions(*tenant_ids)
    tenant_ids.map do |id|
      ActiveRecord::Base.transaction { described_class.with_tenant(id) { [ current_transaction_id, id ] } }
    end
  end

  def tenants_seen_without_an_outer_transaction(*tenant_ids)
    tenant_ids.map { |id| described_class.with_tenant(id) { [ current_transaction_id, id ] } }
  end

  def two_tenants_in_sequence
    described_class.with_tenant(tenant_id) { nil }
    described_class.with_tenant(other_tenant_id) { nil }
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

  it "does not remember the transactional fixture transaction", :aggregate_failures do
    expect(connection.transaction_open?).to be(true)
    expect(connection.pinned).to be(true)
    expect { two_tenants_in_sequence }.not_to raise_error
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

  context "without transactional fixtures" do
    self.use_transactional_tests = false

    before do
      raise "tenancy canaries must run outside transactional fixtures" if connection.transaction_open?
    end

    it "refuses sequential calls with different tenants inside one outer transaction" do
      expect { tenants_seen_in_outer_transaction(tenant_id, other_tenant_id) }
        .to raise_error(described_class::TenantConflict)
    end

    it "refuses a different tenant in a non-joinable transaction" do
      expect(non_joinable_second_block).to eq([ true, false ])
    end

    it "refuses a different tenant after a savepoint that used one rolled back" do
      expect { savepoint_rollback_then_other_tenant }
        .to raise_error(described_class::TenantConflict)
    end

    it "refuses a different tenant from a savepoint inside the block" do
      expect { savepoint_inside_block_other_tenant }
        .to raise_error(described_class::TenantConflict)
    end

    it "refuses a different tenant with a savepoint around the second call" do
      expect { second_call_inside_savepoint(tenant_id, other_tenant_id) }
        .to raise_error(described_class::TenantConflict)
    end

    it "refuses a different tenant with a savepoint around the first call" do
      expect { first_call_inside_savepoint(tenant_id, other_tenant_id) }
        .to raise_error(described_class::TenantConflict)
    end

    it "allows sequential calls with the same tenant inside one outer transaction" do
      expect(tenants_seen_in_outer_transaction(tenant_id, tenant_id)).to eq([ tenant_id, tenant_id ])
    end

    it "allows the same tenant again in one transaction on one transaction ID", :aggregate_failures do
      seen = tenants_seen_in_one_transaction(tenant_id, tenant_id)

      expect(seen.map(&:first).uniq.size).to eq(1)
      expect(seen.map(&:last)).to eq([ tenant_id, tenant_id ])
    end

    it "allows different tenants without an outer transaction", :aggregate_failures do
      seen = tenants_seen_without_an_outer_transaction(tenant_id, other_tenant_id)

      expect(seen.map(&:first).uniq.size).to eq(2)
      expect(seen.map(&:last)).to eq([ tenant_id, other_tenant_id ])
    end

    it "allows different tenants in separate outer transactions", :aggregate_failures do
      seen = tenants_seen_in_separate_transactions(tenant_id, other_tenant_id)

      expect(seen.map(&:first).uniq.size).to eq(2)
      expect(seen.map(&:last)).to eq([ tenant_id, other_tenant_id ])
    end
  end
end
