# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"
  step "Style: Markdown", "test node_modules -nt package-lock.json || npm ci && npm run lint:md"
  step "Guards: Documentation", "npm run docs:check"
  step "Guards: Documentation canary", "script/docs/canary"
  step "Guards: PostgreSQL image", "script/ci/postgres_image_check"
  step "Guards: PostgreSQL image canary", "script/ci/postgres_image_check --canary"
  step "Guards: strong_migrations canary", "script/ci/strong_migrations_canary"
  step "Guards: Migration replay", "script/ci/migration_replay_check"
  step "Guards: Migration replay canary", "script/ci/migration_replay_check --canary"

  step "Guards: Packwerk package graph", "bin/packwerk validate"
  step "Guards: Packwerk dependencies", "script/ci/packwerk_check"
  step "Guards: Packwerk canary", "script/ci/packwerk_canary"
  step "Guards: Packwerk recorded violations", "script/ci/package_todo_check"
  step "Guards: Packwerk recorded violations canary", "script/ci/package_todo_check --canary"
  step "Guards: Packwerk configuration", "script/ci/packwerk_config_check"
  step "Guards: Packwerk configuration canary", "script/ci/packwerk_config_check --canary"

  step "Guards: Lead guard canary", "script/ci/lead_guard_canary"
  step "Guards: OpenCode policy", "script/ci/opencode_policy_check"
  step "Guards: OpenCode policy canary", "script/ci/opencode_policy_check --canary"
  step "Guards: Main ruleset canary", "script/ci/ruleset_check --canary"
  step "Tests: Loop driver", "script/loop/test"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: RSpec", "bin/rails db:test:prepare && bin/db-roles && bin/rspec"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
