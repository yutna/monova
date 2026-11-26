# Monova

Monova is a template for production Rails 8.1 API-only applications.
Clients are first-party apps and machine clients that call a REST API
with bearer tokens. The application is built from Rails engines with
declared boundaries, stores its data in PostgreSQL with row-level
tenancy, and is guarded by CI checks that enforce these rules.

These files are the specification of the template. They describe the
architecture, the contracts, the conventions, and how each rule is
enforced. A repository created from the template keeps them in
`docs/architecture/` and owns them from then on.

`Acme` stands for your application namespace. `billing` and `invoices`
stand for an example engine and resource. Code examples use them so that
no example looks like a real product.

## Principles

1. **The contract comes first.** The OpenAPI 3.1 document, written in
   YAML before the code, is the source of truth for every endpoint.
   Requests and responses are checked against it in tests
   (`02_api_contract.md`).
2. **Every request belongs to one tenant.** The tenant comes from the
   bearer token, never from client input, and PostgreSQL row-level
   security holds even when application code forgets a scope
   (`03_identity_access.md`, `04_data.md`).
3. **Engines with declared, one-way dependencies.** A kernel engine
   (`core`), domain engines and product engines each expose a public
   surface; Packwerk checks that nothing else crosses an engine boundary
   (`01_architecture.md`).
4. **Plain objects around Active Record.** Active Record models keep
   their own invariants. Value objects, command objects and query
   objects carry the rest of the domain logic. There are no repository
   classes (`05_domain.md`).
5. **Tools guard, people decide, AI builds.** Every rule names what
   enforces it. A guard is a tool that fails the build and has a canary
   that proves it fails. People decide what tools cannot check. AI
   writes code and may assist a review, but never counts as a guard
   (`12_enforcement.md`, `15_working_with_ai.md`).
6. **Copy and own.** The template is copied into a new repository, not
   installed as a dependency. After adoption every file is yours,
   security included (`14_workflow.md`).

## File map

| File | Prefix | Covers |
| --- | --- | --- |
| `00_README.md` | | Principles, rule format, statuses, stack, adoption |
| `01_architecture.md` | ARCH | Engines, Packwerk, surfaces, tables, layout |
| `02_api_contract.md` | API | REST, OpenAPI, versions, pages, errors |
| `03_identity_access.md` | AUTH | Tokens, scopes, policies, tenancy |
| `04_data.md` | DATA | Roles, migrations, constraints, IDs, PII, audit |
| `05_domain.md` | DOM | Logic placement, objects, events, outbox |
| `06_async_integration.md` | INT | Jobs, webhooks, outbound HTTP |
| `07_performance.md` | PERF | N+1, query budgets, caching |
| `08_security.md` | SEC | OWASP API Top 10, rate limits, secrets |
| `09_observability_ops.md` | OPS | Logs, health, Dev Container, deploy |
| `10_testing.md` | TS | RSpec levels, contract tests, canaries, CI budget |
| `11_generators.md` | GEN | Engine and endpoint generators |
| `12_enforcement.md` | | Rule to tool to status matrix |
| `13_decisions.md` | ADR | Architecture decision records |
| `14_workflow.md` | WF | Template process versus the adopter's |
| `15_working_with_ai.md` | AI | AI files, task skills, design pack |
| `lessons-learned.md` | | Surprises, root causes, feedback |

## Rule format

Every rule is a level-three heading with an ID, a title, a strength, and
the decision record it implements:

```text
### <PREFIX>-NN — <title> (<STRENGTH> · ADR-NN)
```

- `<PREFIX>` is the topic file's prefix from the file map, and `NN` is a
  two-digit number, never reused.
- **MUST**: breaking it is a defect.
- **SHOULD**: follow it unless the pull request states a reason.
- **MAY**: an accepted option.
- `ADR-NN` names the record in `13_decisions.md` that explains why the
  rule exists. A superseded record is never cited; its replacement is.

Each rule is defined once, in its topic file. Every other file, including
`AGENTS.md` and the AI instruction files, refers to it by ID and never
restates it. `npm run docs:check` fails when a cited ID does not exist,
when an ID is defined twice, when a superseded ADR is cited, or when a
file exceeds its line budget.

### Line budgets

The specification stays short enough to read in one sitting.

| Scope | Budget |
| --- | --- |
| A topic file | 400 lines |
| `12_enforcement.md`, `13_decisions.md` | 600 lines |
| All files in `docs/architecture/` together | 4,500 lines |

## Enforcement statuses

`12_enforcement.md` lists every rule with one of three statuses:

- **enforced**: a CI tool fails the build when the rule is broken, and a
  canary in the same CI run proves that the tool fails on a known
  violation. A tool without a canary does not make a rule enforced.
- **tested in kernel**: the kernel (`core` and the generators)
  implements the behaviour and its own specs prove it. Feature code gets
  it by going through the kernel, which the generators wire in.
- **review**: people check it in review. AI review may assist but never
  counts as a guard.

A rule moves to a stronger status only in the pull request that adds the
tool and its canary. Loosening a guard is decided by people, never by
the pull request that would profit from it.

## Precedence

When guidance conflicts, the first source in this list wins:

1. Current library documentation, for API details.
2. An ADR in `13_decisions.md`.
3. A rule in a topic file.
4. The project's AI instruction files, which cite rules and never
   restate them.
5. General advice and AI skills, including the design skills pack.

A conflict between two ADRs, or between an ADR and a principle, is
settled by a new ADR that supersedes one of them.

## Stack

### Runtimes

Runtimes are pinned to exact versions in `mise.toml`, and every tool
reads them from there.

| Runtime | Version | Pinned in |
| --- | --- | --- |
| Ruby | 4.0.10 | `mise.toml`, `.ruby-version` |
| Node | 26.13.1 | `mise.toml`, `package.json` `engines` and `devEngines` |
| npm | 11.20.0 | `package.json` `packageManager` and `devEngines` |

Node is used only for development tools such as `markdownlint-cli2`;
the application has no JavaScript runtime dependency.

### Libraries

| Purpose | Library |
| --- | --- |
| Framework | Rails 8.1, API-only |
| Web server | Puma, behind Thruster |
| Database | PostgreSQL, for the primary database and the Solid databases |
| Jobs, cache, Action Cable | Solid Queue, Solid Cache, Solid Cable |
| API contract checks | `openapi_first` |
| Authorization | Action Policy |
| Engine boundaries | Packwerk |
| Tests | RSpec and its ecosystem, listed in `10_testing.md` |
| Static checks | RuboCop and its plugins, Brakeman, `bundler-audit` |
| Markdown lint | `markdownlint-cli2`, default rules, no overrides |
| Deployment | Kamal |

Each library is added by the issue that first needs it, and that issue
records its exact version. `10_testing.md` justifies each test gem.
These files name no version for a library; `Gemfile.lock` and
`package-lock.json` are the record.

### Dependency conventions

- Every gem and every npm package is pinned to an exact version in the
  `Gemfile` and `package.json`, not only in the lockfile.
- Both lockfiles are committed. CI installs with a frozen Bundler and
  `npm ci`, so a lockfile that does not match fails the build.
- The `Gemfile` is grouped by purpose, with a comment above each group
  that says what the group is for.
- Upgrades come one package or one peer group per pull request, through
  a dependency bot. A major upgrade always has its own pull request.

### Development environment

Adopters work in a Dev Container: PostgreSQL runs as a service from an
image pinned by version and digest, and Ruby and Node are installed from
`mise.toml`. `bin/ci` runs the same steps inside the container and in
GitHub CI, and a CI job rebuilds the container and runs `bin/ci` in it
whenever a pin file changes, so the container cannot drift
(`09_observability_ops.md`).

## Adopting Monova

### A new application

1. Create a repository from the GitHub template:

   ```sh
   gh repo create my-app --template yutna/monova --private
   ```

2. Open the repository in its Dev Container, run
   `bin/setup --skip-server`, then `bin/ci`. The untouched template is
   green.
3. Rename the `Monova` namespace to your own, replace the credentials,
   the deployment settings and the community files, and keep `bin/ci`
   green.
4. Resolve the dependency set again, pin the result exactly, and commit
   both lockfiles.
5. Generate your engines and endpoints with the generators
   (`11_generators.md`) instead of copying files by hand.
6. Decide who owns the kernel and the guard files, and adapt the AI
   instruction files as `15_working_with_ai.md` describes.
7. Set up logging, error reporting, backups and deployment from
   `09_observability_ops.md` before the first real user.

### After adoption

There is no update tool. A later template release is a reference: read
its release notes and `13_decisions.md`, and port what you want by hand,
in a pull request that runs `bin/ci`. Fixes to the template reach your
copy only that way. Report a vulnerability in the template through its
`SECURITY.md`; keeping your copy secure is your responsibility.

### An existing Rails application

Monova is meant for new applications. An existing Rails API can adopt
it one piece at a time: the guards first, then the kernel, then one
engine moved end to end as the example, then one feature per pull
request. A project that is not a Rails application is out of scope.

## Extension points and out of scope

These are deliberately not part of Monova. Each needs an ADR before it
is added.

- **Browser sessions and cookies**: out of scope. Clients authenticate
  with bearer tokens; a browser front end talks to its own backend,
  which holds the token.
- **Server-rendered HTML**: out of scope; the application is API-only.
- **GraphQL**: out of scope; the API is REST, described by OpenAPI.
- **Database per tenant**: out of scope; tenancy is a row-level
  `tenant_id` with row-level security.
- **Databases other than PostgreSQL**: out of scope; tenancy relies on
  PostgreSQL row-level security.
- **Repository classes**: not used; Active Record is the persistence
  layer.
- **Template update tool**: not provided; adopters copy and own the
  template.
- **Realtime**: Action Cable through Solid Cable is available; a channel
  needs an ADR that covers its authorization.
- **File uploads**: Active Storage direct uploads, with a size limit and
  an allow-list of content types.
