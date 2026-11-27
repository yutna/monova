# 10 — Testing

How the application proves its rules. Tests use RSpec and its ecosystem,
and request specs check traffic against the OpenAPI document with
`openapi_first` (ADR-05). Specs never reach the network (ADR-24), every
custom guard proves it fails (ADR-19), and the suite has a time budget
(ADR-25).

## Terms

| Term | Meaning |
| --- | --- |
| Kernel spec | A spec in `core` that proves a behaviour other rules rely on |
| Guard | A CI tool or check that fails the build when a rule is broken |
| Canary | A known violation that a guard must reject in the same CI run |
| Lane | One RSpec process in `bin/ci`, with its own options |
| Contract coverage | Share of documented responses that a spec produced |

## Rules

### TS-01 — Each behaviour is tested at the cheapest level (MUST · ADR-05)

| Level | Folder | Proves | Database |
| --- | --- | --- | --- |
| Value object | `spec/values/` | Construction, equality, rules (DOM-03) | no |
| Model | `spec/models/` | Constraints and invariants (DATA-07, DOM-02) | yes |
| Policy | `spec/policies/` | Each rule allows and denies (AUTH-06) | yes |
| Command, query | `spec/{commands,queries}/` | One use case (DOM-04) | yes |
| Job | `spec/jobs/` | Runs, retries, runs twice safely (INT-03) | yes |
| Client | `spec/clients/` | Success, timeout, error (INT-13) | no |
| Request | `spec/requests/` | The operation end to end (TS-04) | yes |
| Kernel | `engines/core/spec/` | The behaviours of TS-06 | yes |

- Folders sit in each engine's `spec/` and mirror DOM-01. Serializers
  are proved through request specs, subscribers like jobs (DOM-11).
- A behaviour is proved once, at the lowest level that can see it. A
  request spec does not repeat every validation a model spec proved; it
  proves the operation's statuses, its caller checks and its budgets.
- There are no controller, view, routing or system specs: the
  application is API-only, and request specs replace them.
- Model constraints are proved against the database, not only through
  validations: a spec writes past the validation and expects the
  database error (DATA-07).
- Policy specs use Action Policy's RSpec DSL (`describe_rule`,
  `succeed`, `failed`); a request spec checks that the action is
  authorized with `be_authorized_to`, not every rule again.
- Job specs use the test adapter and perform the job twice, expecting
  the second run to change nothing (INT-03).

### TS-02 — The test gems are fixed, and each has a reason (MUST · ADR-05)

| Gem | Why it is here |
| --- | --- |
| `rspec-rails` | RSpec for Rails: spec types, transactional examples |
| `factory_bot_rails` | Builds records as the runtime role (TS-03) |
| `shoulda-matchers` | One-line specs for associations and validations |
| `webmock` | Blocks real HTTP and stubs outside services (INT-13) |
| `openapi_first` | Contract validation and contract coverage (API-04, TS-04) |
| `prosopite` | Fails specs on N+1 queries (PERF-04) |
| `test-prof` | `let_it_be`, `before_all`, and profilers for slow specs |
| `simplecov` | Line and branch coverage with a floor (TS-08) |
| `parallel_tests` | Runs the suite in several local processes (TS-09) |
| `rubocop-rspec` | Lints spec structure and naming |
| `rubocop-rspec_rails` | Lints Rails-specific spec style |
| `rubocop-factory_bot` | Lints factory definitions and calls |

- These are the only test gems. Another needs an ADR. In particular:
  no rswag (ADR-05), no VCR (stubs come from documentation, INT-13), no
  Capybara (no browser), no `database_cleaner` (transactional examples
  suffice, TS-03), no Faker (random data makes failures hard to repeat;
  factories use sequences).
- Time is controlled with Rails' `travel_to` and `freeze_time`, included
  from `ActiveSupport::Testing::TimeHelpers`; no time gem is added.
- The RuboCop plugins load through the `plugins:` key in `.rubocop.yml`,
  next to the Rails omakase style. A disabled cop needs a comment with
  the reason.
- Each gem is pinned exactly in the `Gemfile`'s test group, with a
  comment per group (`00_README.md`).

### TS-03 — Specs run against PostgreSQL as the runtime role (MUST · ADR-07)

- The test database is PostgreSQL with the roles of DATA-01. The schema
  is loaded from `db/structure.sql` as `acme_migrator`; examples connect
  as `acme_app`, so row-level security binds every spec as it binds
  production. A spec suite that connects as an owner or a superuser
  proves nothing about tenancy.
- Records are built with factories, never Rails fixtures: loading
  fixtures runs `ALTER TABLE ... DISABLE TRIGGER ALL`, which needs a
  superuser, and `acme_app` owns nothing.
- Examples run in a transaction that is rolled back
  (`use_transactional_fixtures`). A factory that creates a tenant-owned
  record runs inside core's test tenancy helper, so the policy's
  `WITH CHECK` passes; `let_it_be` and `before_all` setup does the same.
- `set_config(..., true)` lasts until the outer transaction ends, even
  across a released savepoint, so inside a transactional example a
  tenant would leak into the rest of the example. Core's tenancy helper
  restores the previous `app.tenant_id` when its block ends, and a
  kernel spec proves that a query after the block sees no tenant rows.
- Each engine keeps its specs and factories under
  `engines/<engine>/spec/` (ARCH-09). Root `spec/rails_helper.rb` adds
  every engine's `spec/factories` to factory_bot's
  `definition_file_paths`, and one `bin/rspec` run covers `spec/` and
  `engines/*/spec/`. A spec uses only factories from its own engine and
  the engines it depends on (ARCH-04).

### TS-04 — Every operation has a contract request spec (MUST · ADR-05)

- The request spec setup calls `OpenapiFirst::Test.setup` with the
  bundle and observes the Rails application, so every request and
  response in a request spec is validated. API-04 sets what fails and
  the 100% contract coverage; this rule says what each spec contains.
- Each operation's request spec produces every documented response
  status and checks the response through the contract, not by
  repeating the schema in the spec.
- Core ships shared example groups that every generated request spec
  includes (`11_generators.md`):
  - missing, expired and revoked tokens answer `401`; a token without
    the operation's scope answers `403` (AUTH-04, AUTH-05);
  - an ID from another tenant, and one from the same tenant without
    access, both get the documented answer (AUTH-08);
  - each writing action rejects a field the caller may not set with
    `403` (SEC-01);
  - authenticated responses are `private` (PERF-06);
  - the operation stays within its query budget (PERF-05), with
    Prosopite active (PERF-04).
- Rate limit specs swap the `:null_store` of the test environment for
  an `ActiveSupport::Cache::MemoryStore` around the example and prove
  that each limit answers `429` (SEC-02, SEC-03).
- `openapi_first` checks contract coverage once, in the process that
  called `setup`. Its tracker reaches forked workers but not the
  separate processes that `parallel_tests` starts, each of which would
  check only its own share. Contract coverage is therefore enforced
  only in the single request spec lane of TS-09; under
  `PARALLEL_TEST_GROUPS` the setup sets `report_coverage = false`.

### TS-05 — Examples are independent and repeatable (MUST · ADR-05)

- Examples run in random order; the seed is printed and seeds Ruby's
  random generator, so a failure repeats with `--seed`.
- No spec reaches the network (INT-13). No spec sleeps; time-dependent
  code is tested with `travel_to` or `freeze_time`.
- No spec depends on another's data or order. Shared setup goes through
  `let_it_be` or `before_all`, which roll back with the group.
- A skipped or pending example fails CI: a check in `bin/ci` reads
  RSpec's JSON report and fails when any example is pending. An example
  is deleted, not skipped.
- A flaky spec is fixed or deleted in the next pull request; it is never
  retried automatically.

### TS-06 — Kernel specs prove the behaviours other rules rely on (MUST · ADR-19)

Core's specs prove each of these, and they run in every `bin/ci`:

| Behaviour | Rule |
| --- | --- |
| `acme_app` owns nothing, cannot bypass RLS, run DDL or edit audit | DATA-01 |
| Each table with `tenant_id` has a forced policy; others are global | DATA-03 |
| `data_classes.yml` lists every column in `db/structure.sql` | DATA-11 |
| Filtered parameters and bearer tokens never reach the log | DATA-13, OPS-02 |
| No tenant reads no rows; an insert for another tenant fails | AUTH-09 |
| The tenancy helper restores the previous tenant when its block ends | TS-03 |
| Core's HTTP client raises inside an open primary transaction | INT-06 |
| Each private and reserved address class is refused | INT-09 |
| A job keeps tenant and request ID, logs no arguments | AUTH-11, OPS-02 |

- A kernel spec is a behaviour test, not a guard: it proves core does
  what the rule says. It makes a rule `tested in kernel`
  (`00_README.md`), not `enforced`.
- An adopter who changes core keeps these specs green or changes the
  rule in the same pull request.

### TS-07 — Every custom guard has a canary in the same run (MUST · ADR-19)

- A custom guard is a script under `script/<area>/`. Its canary
  fixtures live next to it in `script/<area>/fixtures/`: one
  clean fixture and one broken fixture per failure the guard reports.
  The application and RSpec never load them.
- `bin/ci` runs the guard on the code, where it must pass, and then its
  canary (a `--canary` mode or a sibling `canary` script), which runs
  the guard on every fixture: the clean one must pass, and each broken
  one must fail with its expected message. A broken fixture that passes
  fails the build.
- A guard without a canary leaves its rule at `review` in
  `12_enforcement.md`, whatever the tool is.
- Third-party tools (RuboCop, Packwerk, Brakeman, `bundler-audit`,
  `strong_migrations`) get a canary the same way before a rule counts
  them as its guard.
- Changing a guard or its canary is a guard change: the reviewer reads
  it as one (`14_workflow.md`).

### TS-08 — Code coverage is measured, with a floor (SHOULD · ADR-05)

- SimpleCov starts before the application loads, tracks line and
  branch coverage, and covers `app/`, `lib/` and `engines/*/app/` and
  `engines/*/lib/`, so a file that no spec loads counts as missed.
- The floors are 90% of lines and 80% of branches, set in SimpleCov's
  `coverage :line` and `coverage :branch` blocks. The floors are only
  raised; lowering one is a guard change (TS-07).
- Coverage shows what no spec runs; it does not prove a behaviour. A
  spec that runs code without an expectation is a review finding
  (`rubocop-rspec` catches the common forms).

### TS-09 — The suite stays within its time budget (MUST · ADR-25)

- `bin/ci` takes at most five minutes in GitHub CI at template size,
  all steps included. A pull request that pushes it over the budget
  makes the suite faster in the same pull request, or records the
  reason and opens an issue.
- RSpec runs in one process in CI, so contract coverage (TS-04) and
  SimpleCov see the whole suite. When one process no longer fits the
  budget, an ADR decides the split, keeping request specs in one lane.
- Developers MAY run `parallel_rspec` locally. Each process gets its
  own database through `TEST_ENV_NUMBER`, and SimpleCov merges the
  workers' results; contract coverage is checked only in CI.
- Slow specs are found with `test-prof`: `EVENT_PROF=sql.active_record`
  and `FPROF=1` show where time and factories go. `let_it_be` replaces
  repeated `let!` setup when a group creates the same records for every
  example.

## Writing specs for a change

1. Find the cheapest level for each behaviour (TS-01).
2. For an operation, write its request spec with core's shared examples
   and its contract (TS-04).
3. Build records with factories, inside the tenancy helper (TS-03).
4. Stub every outside service from its documentation (INT-13).
5. For a new custom guard, add its canary (TS-07).
6. Run `bin/ci` and keep it within the budget (TS-09).
