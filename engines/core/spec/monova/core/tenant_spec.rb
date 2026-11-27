# frozen_string_literal: true

require "rails_helper"

RSpec.describe Monova::Core::Tenant do
  it "connects as the runtime role" do
    expect(ActiveRecord::Base.connection.select_value("SELECT current_user")).to eq("monova_app")
  end

  it "lets the database fill a version 7 UUID for a new row" do
    tenant = described_class.create!(name: "Acme")

    expect(tenant.id).to match(
      /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
    )
  end

  it "keeps the id the database filled" do
    tenant = described_class.create!(name: "Acme")

    expect(tenant.reload.id).to eq(tenant.id)
  end

  it "rejects a blank name" do
    expect(described_class.new(name: "   ")).not_to be_valid
  end

  it "reports a blank name on the name field" do
    tenant = described_class.new(name: "")
    tenant.valid?

    expect(tenant.errors[:name]).to include("can't be blank")
  end
end
