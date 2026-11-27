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

# Migrations: reject an operation that blocks reads or writes while the old
# code still serves requests (DATA-05).
gem "strong_migrations", "2.8.0"

# Deployment: release this application as a Docker container.
gem "kamal", "2.12.0", require: false

# Engines: every engine is a gem without its own release, loaded through one
# glob so a new engine does not edit this file (ARCH-01).
Dir[File.expand_path("engines/*/*.gemspec", __dir__)].sort.each do |gemspec|
  engine = Gem::Specification.load(gemspec)
  gem engine.name, path: File.dirname(gemspec), require: engine.name.sub("_", "/")
end

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

  # Architecture: check the declared engine graph (ARCH-04, ARCH-06).
  gem "packwerk", "3.3.1", require: false
  gem "packwerk-extensions", "0.4.0", require: false
end

group :test do
  # Test: the guard that blocks real HTTP (TS-02, ADR-24).
  gem "webmock", "3.40.0"
  # Test: factories an engine keeps beside its specs (TS-02, TS-03).
  gem "factory_bot_rails", "6.5.1"
end
