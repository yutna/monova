# frozen_string_literal: true

require "rails_helper"

RSpec.describe Monova::Core::Engine do
  it "is loaded by the application" do
    expect(Rails.application.railties.map(&:class)).to include(described_class)
  end

  it "isolates its namespace" do
    expect(described_class).to be_isolated
  end

  it "scopes its routes to the namespace" do
    expect(described_class.config.default_scope).to eq(module: "monova/core")
  end
end
