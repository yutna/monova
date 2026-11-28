# frozen_string_literal: true

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => error
  abort error.to_s.strip
end

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Examples roll back their changes, and no spec loads Rails fixtures
  # (TS-03).
  config.use_transactional_fixtures = true
end

# Every engine keeps its factories beside its specs (TS-03).
FactoryBot.definition_file_paths += Rails.root.glob("engines/*/spec/factories").map(&:to_s)
FactoryBot.reload

# Spec support that changes the suite's behaviour, such as the tenancy
# fixture exemption, lives under spec/support (TS-03).
Rails.root.glob("spec/support/**/*.rb").sort.each { |file| require file }
