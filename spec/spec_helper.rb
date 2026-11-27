# frozen_string_literal: true

require "webmock/rspec"

# No example reaches the network (TS-05, ADR-24).
WebMock.disable_net_connect!

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!

  # Random order, with the seed printed and applied to Ruby's generator, so a
  # failure repeats with `--seed` (TS-05).
  config.order = :random
  Kernel.srand config.seed
end
