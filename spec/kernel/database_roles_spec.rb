# frozen_string_literal: true

require "rails_helper"

# DATA-01, DATA-02 and TS-03: the runtime role owns nothing, has no BYPASSRLS,
# is not a superuser and cannot change the schema. Run the spec with
# `DB_ROLE=monova_migrator` to see every example fail when the connection is
# not the runtime role.
# rubocop:disable RSpec/DescribeClass -- a kernel spec proves the configured
# database role, not a class.
RSpec.describe "Runtime database role" do
  let(:connection) { ActiveRecord::Base.connection }

  def role_attribute(name)
    connection.select_value("SELECT #{name} FROM pg_roles WHERE rolname = current_user")
  end

  it "connects as monova_app" do
    expect(connection.select_value("SELECT current_user")).to eq("monova_app")
  end

  it "owns no table" do
    owned = connection.select_value(<<~SQL)
      SELECT count(*) FROM pg_tables WHERE tableowner = current_user
    SQL

    expect(owned).to eq(0)
  end

  it "is not a superuser" do
    expect(role_attribute("rolsuper")).to be(false)
  end

  it "cannot bypass row-level security" do
    expect(role_attribute("rolbypassrls")).to be(false)
  end

  it "cannot create tables" do
    expect { connection.execute("CREATE TABLE runtime_role_ddl_probe (id integer)") }
      .to raise_error(ActiveRecord::StatementInvalid, /permission denied/i)
  end
end
# rubocop:enable RSpec/DescribeClass
