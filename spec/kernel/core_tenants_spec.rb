# frozen_string_literal: true

require "rails_helper"

# DATA-08, DATA-10 and AUTH-07: the catalog, not the model, is the
# source of truth for core_tenants' primary key and timestamps.
# rubocop:disable RSpec/DescribeClass -- a kernel spec proves the catalog,
# not a class.
RSpec.describe "core_tenants in the catalog" do
  let(:connection) { ActiveRecord::Base.connection }

  def column(name)
    connection.select_one(<<~SQL)
      SELECT data_type, column_default
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'core_tenants'
        AND column_name = #{connection.quote(name)}
    SQL
  end

  it "gives id the uuid type and the uuidv7() default" do
    expect(column("id")).to include(
      "data_type" => "uuid",
      "column_default" => "uuidv7()"
    )
  end

  it "stores created_at and updated_at as timestamp with time zone" do
    %w[created_at updated_at].each do |name|
      expect(column(name)["data_type"]).to eq("timestamp with time zone")
    end
  end

  it "runs the session in UTC" do
    expect(connection.select_value("SHOW TimeZone")).to eq("UTC")
  end
end
# rubocop:enable RSpec/DescribeClass
