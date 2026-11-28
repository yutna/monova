# frozen_string_literal: true

require "rails_helper"
require_relative "../../support/data_classes_catalog"

# DATA-11: every column of every engine's tables has a data class in the
# engine's db/data_classes.yml. The check reads PostgreSQL's catalog, so a
# migration that adds a column without classifying it fails the suite, and
# so does a listed table or column that no longer exists.
# rubocop:disable RSpec/DescribeClass -- a kernel spec proves the catalog,
# not a class.
RSpec.describe "DATA-11 data classes" do
  let(:catalog) { DataClassesCatalog.new(ActiveRecord::Base.connection) }

  it "connects as the runtime role" do
    expect(ActiveRecord::Base.connection.select_value("SELECT current_user")).to eq("monova_app")
  end

  it "reads engine tables from the catalog" do
    expect(catalog.violations).to be_an(Array)
  end

  it "gives every column of every engine table a data class" do
    expect { catalog.check! }.not_to raise_error
  end
end
# rubocop:enable RSpec/DescribeClass
