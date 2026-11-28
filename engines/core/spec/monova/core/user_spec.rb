# frozen_string_literal: true

require "rails_helper"

RSpec.describe Monova::Core::User do
  it "normalises the email by stripping and downcasing it" do
    user = build(:core_user, email: "  Ada.Lovelace@Example.COM  ")

    expect(user.email).to eq("ada.lovelace@example.com")
  end

  it "finds a user by email in any case" do
    user = create(:core_user, email: "ada@example.com")

    expect(described_class.find_by_email("ADA@Example.COM"))
      .to have_attributes(id: user.id, email: "ada@example.com")
  end

  it "stores the email column as ciphertext" do
    user = create(:core_user, email: "ada@example.com")

    stored = described_class.connection.select_value(
      "SELECT email FROM core_users WHERE id = #{described_class.connection.quote(user.id)}"
    )

    expect(stored).not_to include("ada@example.com")
  end

  it "rejects an email that differs only in case from an existing one at the database" do
    create(:core_user, email: "ada@example.com")
    duplicate = build(:core_user, email: "ADA@example.com")
    duplicate.email_digest = described_class.email_digest("ada@example.com")

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "does not authenticate a wrong password" do
    user = create(:core_user, password: "correct horse battery staple")

    expect(user.authenticate("wrong password")).to be(false)
  end
end
