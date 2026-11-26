# 12 — Enforcement

A rule that no tool checks drifts. This file maps every rule to the
guard that is meant to check it, the status that guard gives it, and
the status it has today. It adds no rules: each rule is defined once in
its topic file, with its strength and its ADR, and this file cites it by
ID. Tools guard, people decide, AI builds (ADR-19).

## Statuses

The statuses are the three of `00_README.md`. The tables abbreviate
them:

| In the tables | Status | Meaning |
| --- | --- | --- |
| `enforced` | enforced | A CI tool fails the build, and its canary proves it |
| `kernel` | tested in kernel | Core implements it and core's specs prove it |
| `review` | review | People check it; AI review never counts |

- **Guard** names the tool or the core behaviour the topic file relies
  on. A dash means the topic file names none: the rule stays `review`.
- **Target** is the status the rule gets when that guard ships with its
  canary (TS-07). For `kernel`, the core behaviour ships with its spec
  (TS-06), and feature code that goes around core is still reviewed.
- **Now** is the status on `main`. Nothing is marked stronger than what
  is shipped: a planned guard is not a guard.
- A guard checks only what it checks. Any part of a rule outside the
  guard's reach is reviewed, whatever the row says.

### Moving a row

A row moves to a stronger status only in the pull request that adds the
tool and its canary, and that pull request changes **Now** in the same
diff. In the template's own build only the lead edits this file
(ADR-10), so the lead adds that change to the implementer's pull request
before merging it. A row moves to a weaker status only by a people's
decision, never in the pull request that would profit from it.

### Today

The template ships no engines, no RSpec suite and no kernel yet, so
every rule below is `review` today. The tools `bin/ci` runs now are:

| Tool | Checks | Canary |
| --- | --- | --- |
| RuboCop (Rails omakase) | Ruby style | none |
| Brakeman `--exit-on-warn` | Code security warnings (SEC-08) | none |
| `bundler-audit` | Gems with known advisories (SEC-08) | none |
| `markdownlint-cli2` | Markdown, default rules | none |
| `npm run docs:check` | Rule IDs, ADR citations, line budgets | yes |
| actionlint (GitHub CI) | Workflow files | none |

The process guards of the template's own build (`script/ci/`, the lead
guard, the OpenCode policies, the `main` ruleset) guard the build, not
the application; `docs/development/protocol.md` lists them.

## Matrix

### Architecture

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| ARCH-01 | — | review | review |
| ARCH-02 | Packwerk layer checker (`packwerk-extensions`) | enforced | review |
| ARCH-03 | — | review | review |
| ARCH-04 | `bin/packwerk validate`, `bin/packwerk check` | enforced | review |
| ARCH-05 | `bin/packwerk check` with no todo files | enforced | review |
| ARCH-06 | Packwerk privacy checker, `enforce_privacy` | enforced | review |
| ARCH-07 | — | review | review |
| ARCH-08 | — | review | review |
| ARCH-09 | — | review | review |
| ARCH-10 | `script/arch/growth` on `config/budgets.yml` | enforced | review |

ARCH-10's check is skipped while `config/budgets.yml` holds no values
(`01_architecture.md`); it counts as a guard only once a budget is set
and its canary exceeds one.

### API contract

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| API-01 | — | review | review |
| API-02 | — | review | review |
| API-03 | `redocly lint`, bundle compared with commit | enforced | review |
| API-04 | `openapi_first` test helpers, full coverage | enforced | review |
| API-05 | `oasdiff breaking --fail-on ERR` vs `main` | enforced | review |
| API-06 | Core's cursor helper | kernel | review |
| API-07 | Core's runtime request check | kernel | review |
| API-08 | Core's error responder | kernel | review |
| API-09 | Core's shared codes | kernel | review |
| API-10 | Core's idempotency keys | kernel | review |
| API-11 | Core's `If-Match` handling | kernel | review |
| API-12 | Core's operation resource | kernel | review |
| API-13 | — | review | review |
| API-14 | Core's rate limit headers | kernel | review |

- API-05: oasdiff marks its OpenAPI 3.1 support as beta. Confirm that
  the pinned version reads the bundle before its canary is written; if
  it does not, API-05 stays `review` and an ADR picks another tool.
- API-09: engine codes and their prefixes are reviewed.

### Identity and access

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| AUTH-01 | Core's token store | kernel | review |
| AUTH-02 | Core's token endpoint | kernel | review |
| AUTH-03 | Core's token lifecycle | kernel | review |
| AUTH-04 | Core's base controller | kernel | review |
| AUTH-05 | Core's scope check from the contract | kernel | review |
| AUTH-06 | Action Policy `verify_authorized` | kernel | review |
| AUTH-07 | Core's tenant resolution | kernel | review |
| AUTH-08 | — | review | review |
| AUTH-09 | Kernel spec: RLS without and across tenants | kernel | review |
| AUTH-10 | — | review | review |
| AUTH-11 | Kernel spec: base job keeps the tenant | kernel | review |
| AUTH-12 | — | review | review |
| AUTH-13 | — | review | review |

AUTH-08's cross-tenant request spec is required per endpoint; that each
endpoint has one is reviewed.

### Data

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| DATA-01 | Kernel spec: `acme_app` owns nothing | kernel | review |
| DATA-02 | Kernel spec: role script grants | kernel | review |
| DATA-03 | Kernel spec: catalog of forced policies | kernel | review |
| DATA-04 | CI loads `structure.sql` into an empty DB | enforced | review |
| DATA-05 | `strong_migrations` with `check_down` | enforced | review |
| DATA-06 | — | review | review |
| DATA-07 | — | review | review |
| DATA-08 | Core's table helper, `uuidv7()` default | kernel | review |
| DATA-09 | Core's money value object | kernel | review |
| DATA-10 | Core's `timestamptz`; RuboCop Rails cops | kernel | review |
| DATA-11 | Kernel spec: data classes vs structure | kernel | review |
| DATA-12 | — | review | review |
| DATA-13 | Kernel spec: filtered values not logged | kernel | review |
| DATA-14 | Core's audit table and grants | kernel | review |
| DATA-15 | — | review | review |
| DATA-16 | `bin/ci` replants the seeds | enforced | review |

- DATA-05: a safe operation wrapped in `safety_assured` is reviewed.
- DATA-10: the RuboCop part becomes `enforced` with its own canary.

### Domain

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| DOM-01 | — | review | review |
| DOM-02 | — | review | review |
| DOM-03 | — | review | review |
| DOM-04 | Core's command base class | kernel | review |
| DOM-05 | Core's tenancy transaction | kernel | review |
| DOM-06 | Core's domain errors and responder | kernel | review |
| DOM-07 | — | review | review |
| DOM-08 | — | review | review |
| DOM-09 | Packwerk privacy checker on event constants | enforced | review |
| DOM-10 | Core's `publish` and outbox | kernel | review |
| DOM-11 | Core's delivery table | kernel | review |
| DOM-12 | `bin/packwerk check` | enforced | review |

DOM-09 and DOM-12 are enforced only for constant references; an event
or a call made by name is reviewed (ARCH-08).

### Async and integration

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| INT-01 | Kernel spec over every job class | kernel | review |
| INT-02 | — | review | review |
| INT-03 | — | review | review |
| INT-04 | — | review | review |
| INT-05 | — | review | review |
| INT-06 | Kernel spec: client raises in a transaction | kernel | review |
| INT-07 | — | review | review |
| INT-08 | Core's HTTP client | kernel | review |
| INT-09 | Kernel spec: private addresses refused | kernel | review |
| INT-10 | Core's webhook signer | kernel | review |
| INT-11 | Core's delivery schedule | kernel | review |
| INT-12 | Core's webhooks controller | kernel | review |
| INT-13 | `WebMock.disable_net_connect!` | enforced | review |

INT-03: each job spec runs the job twice (TS-01); that it does is
reviewed.

### Performance

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| PERF-01 | — | review | review |
| PERF-02 | Core's pagination limits; `EXPLAIN` spec | kernel | review |
| PERF-03 | Strict loading in core's serializer | kernel | review |
| PERF-04 | Prosopite with `raise = true` in specs | enforced | review |
| PERF-05 | Core's query budget matcher | kernel | review |
| PERF-06 | — | review | review |
| PERF-07 | Core's tenant-keyed cache | kernel | review |
| PERF-08 | — | review | review |

PERF-04's opt-outs (`prosopite: false`) are reviewed for their stated
reason.

### Security

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| SEC-01 | — | review | review |
| SEC-02 | Core's base controller `rate_limit` | kernel | review |
| SEC-03 | Core's sensitive-flow limit helper | kernel | review |
| SEC-04 | — | review | review |
| SEC-05 | Core's error responder | kernel | review |
| SEC-06 | Kernel spec: every route in the bundle | kernel | review |
| SEC-07 | — | review | review |
| SEC-08 | Brakeman `--exit-on-warn`, `bundler-audit` | enforced | review |
| SEC-09 | Core's direct upload endpoint | kernel | review |

SEC-08's tools already run in `bin/ci`; the rule stays `review` until a
canary proves that each one fails (`08_security.md`).

### Observability and operations

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| OPS-01 | Pin check in `bin/ci`; Dev Container CI job | enforced | review |
| OPS-02 | Kernel spec: log output filtered | kernel | review |
| OPS-03 | Core's base controller and base job | kernel | review |
| OPS-04 | Core's error responder | kernel | review |
| OPS-05 | — | review | review |
| OPS-06 | — | review | review |
| OPS-07 | — | review | review |
| OPS-08 | — | review | review |
| OPS-09 | — | review | review |

OPS-07 to OPS-09 are about a deployed application; the template has
none, so the adopter's review and runbooks check them.

### Testing

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| TS-01 | — | review | review |
| TS-02 | Frozen Bundler install; RuboCop plugins | enforced | review |
| TS-03 | Kernel spec: tenancy helper restores | kernel | review |
| TS-04 | `openapi_first` contract coverage at 100% | enforced | review |
| TS-05 | `bin/ci` fails on a pending example | enforced | review |
| TS-06 | The kernel specs of the TS-06 table | kernel | review |
| TS-07 | — | review | review |
| TS-08 | SimpleCov floors | enforced | review |
| TS-09 | — | review | review |

- TS-02: that no other test gem is added is reviewed.
- TS-07 is the rule that makes the others count; the gate checks it.
- TS-09: the five-minute budget is read from the CI run in review.

### Generators

| Rule | Guard | Target | Now |
| --- | --- | --- | --- |
| GEN-01 | Generator specs for each refusal | kernel | review |
| GEN-02 | `script/generators/smoke` | enforced | review |
| GEN-03 | `script/generators/smoke` | enforced | review |
| GEN-04 | `script/generators/smoke` | enforced | review |
| GEN-05 | `script/generators/smoke` | enforced | review |
| GEN-06 | `script/generators/smoke` | enforced | review |
| GEN-07 | — | review | review |
| GEN-08 | — | review | review |

- GEN-01: an engine or an endpoint added by hand is caught in review.
- GEN-07 is the rule that the smoke step runs; review checks that the
  CI job's paths cover the generators.

### Workflow and AI

`14_workflow.md` and `15_working_with_ai.md` add their rows here when
they are drafted.

## Canaries

Every guard marked `enforced` has a canary in the same CI run (TS-07):

- A custom guard keeps its fixtures in `script/<area>/fixtures/` and its
  canary runs right after the guard in `bin/ci`.
- A third-party tool (RuboCop, Packwerk, Brakeman, `bundler-audit`,
  `strong_migrations`, oasdiff, Prosopite, SimpleCov) gets a fixture
  with one known violation, and the canary fails unless the tool
  rejects it.
- Every guard and every canary reads the inputs it found and fails on an
  empty set, so a wrong path cannot pass by checking nothing.
- A guard message names the rule ID it protects.

Changing a guard, its canary or a row of this file is a guard change:
the reviewer says so and reads it as one (`docs/development/protocol.md`
§3 for the template; the adopter's own process after adoption).

## The gate

`bin/ci` is the gate for every pull request, in the Dev Container and in
GitHub CI alike (OPS-01). A pull request merges only when it is green.

Before a release, a reviewer who did not write the changes audits the
milestone:

1. Every row marked `enforced` has its tool in `bin/ci` and a canary
   that fails without it.
2. Every row marked `kernel` has a core spec that proves it.
3. No row is stronger than what is on `main`.
4. `bin/ci` passes on a clean checkout.

A finding that a row overclaims blocks the release until the row or the
guard is fixed.
