# 13 — Decisions

Architecture decision records settle the questions where reasonable
people, or general advice, disagree. An ADR outranks a rule
(`00_README.md`, precedence), and every rule names the ADR it
implements.

## Lifecycle

- An ADR is `Accepted` or `Superseded by ADR-NN`. Its number is never
  reused or renumbered, because rules cite it.
- Until the first release of the template, its ADRs are edited in place,
  and a topic file draft may add the ADRs it needs.
- From the first release on, and in every adopted copy, a decision
  changes only through a new ADR. The same pull request marks the old
  one `Superseded by ADR-NN` and moves every rule that cited the old one
  to the new one.
- `npm run docs:check` fails when a rule or a control file cites an ADR
  that does not exist or that is superseded.
- A conflict between two ADRs, or between an ADR and a principle, is
  settled by a new ADR, never by a rule or a code comment.

## Template for a new ADR

```text
### ADR-NN — <decision as a short sentence>

Status: Accepted

**Context.** What forces the choice.

**Decision.** One paragraph.

**Consequences.** What gets easier, what gets harder, what to watch.
```

## Scope of the records

ADR-01 to ADR-09 and ADR-15 onwards apply to the template and to every
application made from it. ADR-10 to ADR-14 record how the template
repository itself is built; an adopted copy does not inherit them, and
`14_workflow.md` says what an adopter keeps.

| Owner decision | Record |
| --- | --- |
| D1 to D14 (2026-11-26) | ADR-01 to ADR-14, in the same order |

## Records

### ADR-01 — The template is copied and owned

Status: Accepted

**Context.** A template can be installed as a dependency that updates
itself, or copied once. An update tool must merge upstream changes into
code that every adopter has changed, and it needs its own versioned
interface to stay correct.

**Decision.** Monova is a GitHub template repository. An adopter
creates a repository from it, and from then on every file belongs to the
adopter, the kernel and the guards included. There is no update tool. A
later template release is a reference that the adopter ports by hand,
reading its release notes and these records.

**Consequences.** No update tool to build or keep compatible, and an
adopter can change anything. Fixes and security patches do not reach
adopted copies by themselves; the release notes must say clearly what
changed and why.

### ADR-02 — Clients are first-party apps and machine clients

Status: Accepted

**Context.** Browser sessions, third-party delegated access and
first-party clients need different authentication flows, and supporting
all of them multiplies the attack surface.

**Decision.** The API serves first-party apps (mobile, desktop, or the
backend of a web front end) and machine clients. Both authenticate with
bearer tokens in the `Authorization` header. There are no cookies, no
browser sessions and no third-party OAuth authorization server.

**Consequences.** No CSRF defence and no session store are needed.
A browser front end needs its own backend to hold the token. Delegated
access for third parties needs a new ADR.

### ADR-03 — REST described by an OpenAPI 3.1 document written first

Status: Accepted

**Context.** An API contract can be generated from code or written
before it. A generated contract describes whatever the code happens to
do, including its accidents.

**Decision.** The API is REST over JSON. Its contract is an OpenAPI 3.1
document in YAML, written before the code it describes and kept in the
repository as the source of truth. Code and tests follow the document;
the document is never generated from code.

**Consequences.** Clients can be built and reviewed from the contract
before the endpoint exists, and a contract change is visible in review.
Every endpoint change edits the YAML first. GraphQL is out of scope
(ADR-20).

### ADR-04 — PostgreSQL for every database

Status: Accepted

**Context.** Rails 8 runs its queue, cache and Action Cable adapters
(Solid Queue, Solid Cache, Solid Cable) on a SQL database instead of
Redis. Tenancy (ADR-07) relies on row-level security, which only
PostgreSQL among the Rails databases offers.

**Decision.** PostgreSQL holds the primary database and the Solid Queue,
Solid Cache and Solid Cable databases, each as its own database. There
is no Redis and no second database engine.

**Consequences.** One engine to run, back up, tune and monitor. Solid
Queue takes jobs with `FOR UPDATE SKIP LOCKED`, so workers do not block
each other. A very high job or cache load may need a new ADR for a
dedicated store.

### ADR-05 — RSpec, and contract checks with openapi_first

Status: Accepted

**Context.** Rails ships Minitest; RSpec has the larger ecosystem for
API work. Contract checks can generate the document from specs (rswag)
or check traffic against a document written first (ADR-03).

**Decision.** Tests use RSpec and its ecosystem, each gem justified in
`10_testing.md`. Request specs check every request and response against
the OpenAPI document with `openapi_first`, which supports OpenAPI 3.0
and 3.1 and reports which parts of the document the tests covered.
rswag is not used.

**Consequences.** The document stays the source of truth, and an
undocumented response fails a test. Adopters who know only Minitest have
one more tool to learn.

### ADR-06 — Opaque tokens stored as digests, scopes, Action Policy

Status: Accepted

**Context.** A self-contained token (JWT) cannot be revoked before it
expires without a server-side list, which removes its advantage. A
token stored in plain text leaks every client when the database leaks.

**Decision.** Access tokens are opaque random strings. The database
stores only a digest of each token, with its owner, tenant, scopes and
expiry. A request is authenticated by looking the digest up, then
authorized twice: the token's scopes limit what the client may do, and
Action Policy policy classes decide what the caller may do to each
record.

**Consequences.** Revocation is a row update and takes effect on the
next request. Every request reads the token row, so the lookup must be
indexed and cheap. Authorization lives in policy classes, not in
controllers.

### ADR-07 — Row-level tenancy with PostgreSQL row-level security

Status: Accepted

**Context.** A forgotten `where(tenant_id: ...)` in application code
leaks one tenant's data to another. A database per tenant isolates
better but multiplies migrations, connections and backups.

**Decision.** Every tenant-owned table has a `tenant_id` column and a
row-level security policy from the first migration. The runtime
database role does not own the tables and has no `BYPASSRLS`, so the
policies hold for it; a separate migrator role owns the schema. The
tenant is set for each transaction from the token, in background jobs
too, never from client input. A re-runnable script creates the roles.

**Consequences.** A missing scope in Ruby returns no rows instead of
another tenant's rows. Every query runs inside a transaction that set
the tenant, and tests must cover that path. Cross-tenant work, such as
operator reports, needs an explicit, audited path.

### ADR-08 — Engines with declared dependencies, checked by Packwerk

Status: Accepted

**Context.** A large Rails application without boundaries becomes one
tangle where any class may call any other. Engines give a boundary in
the file layout, but Ruby does not stop one engine from reaching into
another.

**Decision.** The application is built from Rails engines of three
kinds: the kernel `core`, which depends on nothing in the repository;
domain engines, which hold business concepts that several engines
share; and product engines, which hold one product area and its
endpoints. Each engine declares its dependencies in its `package.yml`,
and Packwerk fails the build on a reference that the declared graph
does not allow. Public-surface checks come from `packwerk-extensions`.

**Consequences.** Engines can be added, split or removed on their own,
and sharing code across a boundary is a reviewed change to a public
surface. The dependency lists must be maintained.

### ADR-09 — Plain objects around Active Record, no repositories

Status: Accepted

**Context.** Fat models and fat controllers mix concerns. Repository
classes on top of Active Record duplicate what Active Record already
does and hide its query interface.

**Decision.** Active Record models keep their own invariants:
validations, associations and database constraints. Value objects,
command objects and query objects carry the remaining domain logic.
Controllers only translate HTTP to a command or a query and back. There
are no repository classes.

**Consequences.** Each class has one job and can be tested at the
cheapest level. The object kinds and where each one lives are defined
in `05_domain.md`, and reviews check that logic lands there.

### ADR-10 — Only the lead edits the specification and control files

Status: Accepted. Applies to the template repository only.

**Context.** The template is built by an AI lead and an AI implementer.
An implementer that may edit its own rules or guards can make a failing
check pass by weakening it.

**Decision.** In the template repository, only the lead edits
`docs/architecture/`, `docs/development/`, the AI instruction files,
the agent configuration and the issue and pull request templates. The
implementer edits everything else. OpenCode policies and the lead's
hook enforce the split.

**Consequences.** A guard cannot be loosened by the change that would
profit from it. Every specification change waits for the lead.

### ADR-11 — A fresh headless lead run for each action

Status: Accepted. Applies to the template repository only.

**Context.** A long-running lead session carries a growing context,
costs more per step and drifts from the state on GitHub.

**Decision.** A timer starts a fresh headless Claude Code lead run that
reads the state from GitHub, takes one action (review, dispatch, plan,
gate or record) and ends. OpenCode implements one issue per pull
request, started by the lead as its own process.

**Consequences.** Each run starts from GitHub and the handoff note, not
from memory, so the state must live there. Work proceeds one step per
tick, which is slower than a session that does several in a row.

### ADR-12 — The lead merges and closes milestones after the gate

Status: Accepted. Applies to the template repository only.

**Context.** A loop that waits for a person to merge stops whenever the
person is away. A lead that merges its own reviews needs an independent
check before a release.

**Decision.** The lead merges a pull request when its review approves it
and CI is green. When every issue of a milestone is closed, a fresh
gate run without the lead's context audits the milestone; the lead
closes it, which publishes the release, only after the gate passes.

**Consequences.** Releases do not wait for the owner. The gate can
disagree with the lead, and a blocking finding reopens work in the same
milestone.

### ADR-13 — Owner decisions go through owner-decision issues

Status: Accepted. Applies to the template repository only.

**Context.** The loop runs unattended, so a question asked in a chat has
nobody to answer it.

**Decision.** The lead asks the owner only for the decisions listed in
the development protocol, through a GitHub issue labelled
`owner-decision` with options and a recommendation. Everything else the
lead decides and records in an ADR or a pull request.

**Consequences.** The owner's questions are in one place and the loop
keeps working on what does not depend on them. The lead must record its
own decisions where the next run can find them.

### ADR-14 — The build uses the owner's personal Claude limits

Status: Accepted. Applies to the template repository only.

**Context.** The loop spends the owner's personal Claude usage, which
other work also needs.

**Decision.** The loop driver reads the usage that each headless run
reports, stops starting runs at 95% of the weekly limit and resumes
after the reset, and waits for the reset when the five-hour limit is
reached.

**Consequences.** The build never exhausts the owner's weekly limit, and
it pauses near the end of a busy week.

### ADR-15 — Rails 8.1 in API-only mode, Puma behind Thruster

Status: Accepted

**Context.** Clients are apps and machines (ADR-02), not browsers that
render HTML.

**Decision.** The application is a Rails 8.1 API-only application. It
renders JSON only, with no views, assets or cookies middleware. Puma
serves it behind Thruster in the container.

**Consequences.** A smaller middleware stack and attack surface.
Server-rendered HTML needs a new ADR (ADR-20).

### ADR-16 — Exact versions and frozen installs

Status: Accepted

**Context.** A version range lets an install pick up a release nobody
reviewed, so two machines can run different code from the same commit.

**Decision.** Runtimes are pinned in `mise.toml`. Every gem and npm
package is pinned to an exact version in the `Gemfile` and
`package.json`, both lockfiles are committed, and CI installs with a
frozen Bundler and `npm ci`. Upgrades arrive one package or peer group
per pull request through a dependency bot; a major upgrade always has
its own pull request.

**Consequences.** Builds are reproducible and every upgrade is reviewed.
Upgrade pull requests are frequent, and someone must merge them.

### ADR-17 — Development in a Dev Container proven in CI

Status: Accepted

**Context.** Hand-built development machines drift from CI and from each
other, and a container definition that nothing runs rots.

**Decision.** Adopters develop in a Dev Container: PostgreSQL as a
service from an image pinned by version and digest, Ruby and Node from
`mise.toml`. `bin/ci` runs the same steps inside the container and in
GitHub CI. A CI job rebuilds the container and runs `bin/ci` in it
whenever a pin file changes.

**Consequences.** A new contributor gets a working environment in one
step, and a broken container fails CI. The template's own build loop
runs on the host with the same pins, so the CI job is what keeps the
container honest.

### ADR-18 — Deploy with Kamal

Status: Accepted

**Context.** Rails 8 ships Kamal as its default deployment tool. A
managed platform adds cost and lock-in that a template should not
impose.

**Decision.** The template deploys a container image to servers with
Kamal, which provides zero-downtime deploys and rolling restarts. The
deployment settings are placeholders that each adopter replaces.

**Consequences.** Any server that runs containers can host the
application. The adopter operates the servers, backups and monitoring
that `09_observability_ops.md` describes.

### ADR-19 — Tools guard, people decide, AI builds

Status: Accepted

**Context.** A rule that only a reviewer remembers is broken sooner or
later. AI assistants write code fast but can be wrong with confidence,
and an AI review is not independent of an AI author.

**Decision.** Every rule names what enforces it. A rule is enforced
only when a CI tool fails on a violation and a canary in the same run
proves that the tool fails. People decide what no tool can check. AI
writes code and may assist a review, but never counts as a guard. A
guard is loosened only by people, never by the pull request that would
profit from it.

**Consequences.** The enforcement matrix (`12_enforcement.md`) shows
honestly what is guarded and what is not. Each new guard costs a tool
and a canary.

### ADR-20 — What is deliberately out of scope

Status: Accepted

**Context.** Every feature a template ships is a feature every adopter
must understand, secure and maintain.

**Decision.** Monova does not include browser sessions and cookies,
server-rendered HTML, GraphQL, a database per tenant, databases other
than PostgreSQL, repository classes or a template update tool. A
realtime channel through Action Cable and file uploads through Active
Storage are available but need the controls their topic files set.
Adding anything from the excluded list needs a new ADR.

**Consequences.** The template stays small enough to understand in full.
An adopter who needs an excluded feature records why in an ADR and owns
its design.

### ADR-21 — Personal data is classified, encrypted and kept briefly

Status: Accepted

**Context.** An API that stores people's data is liable for every copy
of it: in columns, logs, job queues, caches and backups. Data nobody
classified is copied freely, and data nobody deletes is kept forever.

**Decision.** Every column has a data class. Sensitive values are
encrypted with Active Record encryption, values that are only compared
are stored as keyed digests, and personal values never leave their
table for logs, jobs, caches or events. Changes that matter leave an
append-only audit event without personal values, and every kind of data
has a retention period after which a recurring job deletes it.

**Consequences.** A leaked log or database copy exposes far less, and an
erasure request has a defined path. Every new column needs a class, and
encrypted columns cannot be searched except through a digest.
