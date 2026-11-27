source "https://rubygems.org"

# Framework and server: Rails, the web server in front of it, and boot support.
gem "rails", "8.1.4.1"
gem "puma", "8.1.3"
gem "thruster", "0.1.28", require: false
gem "bootsnap", "1.26.2", require: false
gem "tzinfo-data", "1.2026.6", platforms: %i[ windows jruby ]

# Data: the database, and the database-backed cache, job and Action Cable stores.
gem "pg", "1.7.0"
gem "solid_cache", "1.0.10"
gem "solid_queue", "1.7.2"
gem "solid_cable", "4.1.0"

# Deployment: release this application as a Docker container.
gem "kamal", "2.12.0", require: false

group :development, :test do
  # Development and test: the debugger, the security scans, the style linter
  # and the spec runner (TS-02).
  gem "debug", "1.11.1", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", "8.1.1", require: false
  gem "bundler-audit", "0.9.3", require: false
  gem "rubocop-rails-omakase", "1.1.0", require: false
  gem "rubocop-rspec", "3.10.2", require: false
  gem "rubocop-rspec_rails", "2.33.0", require: false
  gem "rspec-rails", "8.1.0"
end

group :test do
  # Test: the guard that blocks real HTTP (TS-02, ADR-24).
  gem "webmock", "3.40.0"
end
