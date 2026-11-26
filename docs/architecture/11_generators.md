# 11 — Generators

Engines and endpoints are created by generators that live in core. A
generator that emits code breaking a rule would start every new engine
broken, so generators read the same sources the application reads, and
CI runs them end to end.

```sh
bin/rails generate core:domain_engine customers                  # GEN-03
bin/rails generate core:product_engine billing                   # GEN-04
bin/rails generate core:endpoint billing invoices --actions=list,show,create \
  --fields=number:string:internal amount:decimal:internal       # GEN-06
bin/rails destroy core:endpoint billing invoices --actions=list  # GEN-01
```

## Rules

### GEN-01 — New engines and endpoints come from the generators (MUST · ADR-08)

- The generators live in `engines/core/lib/generators/core/<name>/`, as
  `<name>_generator.rb` with a `templates/` folder. Rails finds them
  under the `generators/` folder of every load path, so `core:<name>`
  works from the root without a registration step.
- A new engine or a new endpoint starts from a generator, never from a
  copy of another engine. A pull request that adds one by hand is
  returned in review.
- The engine generators write their own templates. They do not wrap
  `rails plugin new`, whose dummy application, `test/` folder and
  gemspec dependencies break ARCH-01 and ADR-05.
- Every generator writes files only with Thor actions that
  `bin/rails destroy` can reverse, so `destroy` with the same arguments
  removes what `generate` wrote, including inserted lines.
- Thor's `run` executes nothing on `destroy`. A generator's last step
  refreshes what derives from its files (`bundle install`,
  `redocly bundle`) in both directions, so `destroy` leaves no stale
  `Gemfile.lock` or bundle.
- A generator refuses, before it writes anything:
  - an engine name that exists, is not `snake_case`, or is reserved
    (`core`, `app`, `engines`, `openapi`, `v1`);
  - a resource whose singular equals its plural (`news`), because Rails
    then shifts every route name;
  - an action or a resource the engine already has, so one run never
    overwrites a file;
  - an endpoint in a domain engine (ARCH-02).

### GEN-02 — Templates read the sources instead of copying them (MUST · ADR-08)

Templates never hard-code what the application already declares:

- the namespace comes from `Rails.application.class.module_parent_name`
  (`Acme`), so renaming the namespace at adoption needs no template
  change; an engine is `Acme::<Engine>` in gem `acme_<engine>`;
- the layers come from `packwerk.yml` (ARCH-04);
- scope names follow AUTH-05, error codes API-09, the `operationId`
  form API-03;
- the primary key type comes from the root `config/application.rb`,
  whose `config.generators` sets `orm :active_record,
  primary_key_type: :uuid` and `test_framework :rspec`. Rails' own
  `model` and `migration` generators read the same option, so they
  emit `id: :uuid` too (DATA-08).

When one of these sources changes, the generated code changes with it.

### GEN-03 — core:domain_engine emits a domain engine (MUST · ADR-08)

```text
engines/customers/
├── acme_customers.gemspec   # no runtime dependencies (ARCH-01)
├── lib/acme/customers.rb
├── lib/acme/customers/engine.rb
├── package.yml              # layer: domain, depends on engines/core
├── AGENTS.md                # GEN-05
├── app/public/acme/customers/
├── app/{models,commands,queries,values,policies}/acme/customers/
├── config/locales/en.yml
├── db/migrate/
├── db/data_classes.yml      # empty list (DATA-11)
└── spec/factories/
```

- `engine.rb` calls `isolate_namespace Acme::Customers` and appends
  `db/migrate` to the application's migration paths in an initializer,
  so migrations run where they live (ARCH-07).
- The root `Gemfile` loads the engine through its glob (ARCH-01), so the
  generator does not edit it. `Gemfile.lock` changes; the generator runs
  `bundle install` and the lockfile is committed with the engine.
- A domain engine has no routes, controllers, serializers or OpenAPI
  fragment (ARCH-02).

### GEN-04 — core:product_engine emits a product engine and mounts it (MUST · ADR-08)

The product engine has the domain engine's files with `layer: product`,
plus:

```text
engines/billing/
├── app/{controllers,serializers}/acme/billing/
├── config/routes.rb         # empty draw block
└── openapi/paths.yaml       # empty paths map (API-03)
```

- The generator inserts one line into the root `config/routes.rb`,
  mounting the engine under `/v1` (API-01, ARCH-09). It inserts nothing
  else outside the engine folder.
- `package.yml` depends only on `engines/core`. A further dependency, on
  a domain engine or another product engine's surface, is added by hand
  in a pull request that says it is a guard change (ARCH-04).
- The engine starts with no operation, so the contract coverage of
  API-04 and the budgets of PERF-05 are untouched until GEN-06 runs.

### GEN-05 — Every engine gets an AGENTS.md for its kind (MUST · ADR-19)

Each engine generator writes `engines/<engine>/AGENTS.md`, a short guide
for an AI agent working inside that engine:

- the engine's kind and what that kind may and may not hold
  (ARCH-02, ARCH-03), as rule IDs;
- its declared dependencies, read from its `package.yml` at generation
  time, and a pointer to that file as the record;
- the folders of DOM-01 and the rules to read before changing each;
- the commands that check the engine: `bin/rspec engines/<engine>`,
  `bin/packwerk check engines/<engine>`, then `bin/ci`.

It cites rules by ID and restates none (`00_README.md`). After
generation it belongs to the engine and is edited like any other file;
`15_working_with_ai.md` says how it relates to the root `AGENTS.md`.

### GEN-06 — core:endpoint emits one complete, passing operation (MUST · ADR-03)

For `core:endpoint <engine> <resource> --actions=<list>` the generator
writes, per action (`list`, `show`, `create`, `update`, `delete`):

- **Contract**: the operation in `engines/<engine>/openapi/paths.yaml`
  with `operationId` `<engine>_<verb>_<resource>`, the engine tag, the
  `security` scopes, `additionalProperties: false`, and every response
  with its problem codes (API-03, AUTH-05, API-09).
- **Root contract**: the `/v1` path in `openapi/v1.yaml` that refers to
  the engine's path item, then `redocly bundle` refreshes
  `openapi/v1.bundle.yaml`.
- **Route**: the resource route in the engine's `config/routes.rb`
  (API-01).
- **Controller**: the action, inheriting core's base controller; writing
  actions read the body with `params.expect` (SEC-01).
- **Policy**: the rule in `app/policies/` (AUTH-06).
- **Logic**: a query for reads, a command for writes (DOM-04, DOM-07).
- **Serializer**: the resource's fields, `secret` columns left out
  (PERF-03, DATA-11).
- **Budget**: the `queries:` entry in `config/budgets.yml` (PERF-05).
- **Copy**: the engine's error codes in its locale file (API-09).
- **Request spec**: every documented status, with core's shared
  examples (TS-04).

- `list` emits cursor pagination with a sort column and `id` as the
  tie breaker (API-06); `create` requires an idempotency key (API-10);
  `update` and `delete` require `If-Match` (API-11).
- For a new resource the generator also writes the model, its factory
  and its migration. The migration creates the `<engine>_<resources>`
  table with a UUID key, `tenant_id` and `add_tenant_policy`
  (DATA-03, DATA-08) and passes `strong_migrations` (DATA-05).
- Every `--fields` entry is `name:type:class`. The class is written to
  `db/data_classes.yml`; a field without a class is refused, so no
  column is generated unclassified (DATA-11).
- The generated request spec passes against the generated code before
  anyone edits it, and contract coverage stays at 100% (API-04).

### GEN-07 — CI runs the generators end to end (MUST · ADR-19)

`script/generators/smoke` is a `bin/ci` step. In a scratch copy of the
checkout it:

1. generates a domain engine and a product engine, and declares the
   domain engine as the product engine's dependency;
2. generates every action of one resource in the product engine;
3. runs RuboCop, `bin/packwerk validate` and `check`, `redocly lint`,
   the bundle comparison of API-03 and the new engines' specs;
4. runs `bin/rails destroy` for each generator in reverse order and
   checks that the scratch tree matches the checkout again.

- Generating an engine changes `Gemfile.lock`, so the smoke step alone
  runs with `BUNDLE_FROZEN=false`, in the scratch copy; every other
  step keeps frozen installs (ADR-16). It refuses to start on a dirty
  checkout and never writes to the real one.
- CI runs it on pull requests that touch `engines/core/lib/generators/`,
  core's base classes, `openapi/` or `config/application.rb`, and
  nightly. The skip lives in the job's `if:`, never inside the step,
  so a skipped run cannot report success.
- Each refusal of GEN-01 has a generator spec in core.

`12_enforcement.md` records the status of each GEN rule.

### GEN-08 — Generated files belong to their engine (SHOULD · ADR-01)

- A generator runs once per engine or endpoint. Afterwards the files are
  ordinary code; nobody regenerates over them, and a template change does
  not reach engines that already exist.
- When a template improves, existing engines adopt the change by hand,
  in a pull request that runs `bin/ci`, as adopters port template
  releases (`00_README.md`).
- Kernel changes that every engine needs go into core's base classes and
  shared examples, which existing engines inherit, not into templates
  alone.
