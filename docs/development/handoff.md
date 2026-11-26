# Handoff

The current state of the Monova build, for a new lead session. GitHub
and `git log` win when this note disagrees with them. The process is in
[protocol.md](protocol.md).

## Goal

Monova becomes a production-ready Rails 8.1 API-only template built from
engines, with a specification in `docs/architecture/` and guards that
enforce it. Claude leads and OpenCode implements, unattended, until the
template is complete. The owner is asked only for protocol §8 decisions.

## Decisions (owner, 2026-11-26)

| ID | Decision |
| --- | --- |
| D1 | GitHub template repo, copy-and-own; no kernel-update tool in v1 |
| D2 | Clients: first-party apps and machine clients, bearer tokens |
| D3 | REST; OpenAPI 3.1 design-first YAML is the source of truth |
| D4 | PostgreSQL for primary and Solid* databases |
| D5 | RSpec; contract checks with `openapi_first`, not rswag |
| D6 | Opaque tokens stored as digests, scopes; Action Policy |
| D7 | Row-level `tenant_id` plus PostgreSQL RLS from day one |
| D8 | Engines: kernel `core`, domain engines, product engines; Packwerk |
| D9 | AR invariants; value, command and query objects; no repositories |
| D10 | Only the lead edits the specification and control files |
| D11 | Fresh headless lead run per action; OpenCode implements |
| D12 | The lead merges and closes milestones after the gate passes |
| D13 | Owner decisions through `owner-decision` issues only |
| D14 | Use the personal Claude limits; stop at 95% of the weekly limit |

Details behind D7: the runtime database role does not own tables and has
no `BYPASSRLS`; the tenant is set per transaction from the token, in jobs
too; a separate migrator role; a re-runnable role script.

Dependency conventions: every gem and npm package pinned to an exact
version; lockfiles committed; frozen installs in CI; the Gemfile grouped
by purpose with a comment per group; the RSpec ecosystem used fully
(rspec-rails, factory_bot_rails, shoulda-matchers, webmock, test-prof,
rubocop-rspec and friends), each justified in the testing file.

Markdown: `markdownlint-cli2` with default rules and no rule overrides.
Node 26.13.1 (latest LTS) and Ruby 4.0.9 pinned in `mise.toml`.

## Specification outline

Budget: at most 4,500 lines in total; topic files at most 400 lines;
the enforcement matrix and the ADR file at most 600.

| File | Prefix | Covers |
| --- | --- | --- |
| `00_README.md` | | Principles, rule format, statuses, stack, adoption |
| `01_architecture.md` | ARCH | Engines, Packwerk, surfaces, tables, layout |
| `02_api_contract.md` | API | REST, OpenAPI, versions, pages, errors, caching |
| `03_identity_access.md` | AUTH | Tokens, scopes, policies, tenancy, BOLA |
| `04_data.md` | DATA | Roles, migrations, constraints, IDs, PII, audit |
| `05_domain.md` | DOM | Logic placement, objects, events, outbox |
| `06_async_integration.md` | INT | Jobs, webhooks, outbound HTTP |
| `07_performance.md` | PERF | N+1, query budgets, caching, serialization |
| `08_security.md` | SEC | OWASP API Top 10, rate limits, secrets |
| `09_observability_ops.md` | OPS | Logs, tracing, health, deploy, backups |
| `10_testing.md` | TS | RSpec levels, contracts, canaries, CI budget |
| `11_generators.md` | GEN | Engine and endpoint generators |
| `12_enforcement.md` | | Rule to tool to status matrix |
| `13_decisions.md` | ADR | Architecture decision records |
| `14_workflow.md` | WF | Template process versus the adopter's |
| `15_working_with_ai.md` | AI | AI files, task skills, pack versus project |
| `lessons-learned.md` | | Surprises, root causes, feedback |

The development environment is a Dev Container (OPS): a PostgreSQL
service pinned by version and digest, Ruby and Node installed from
`mise.toml`, and a CI job that rebuilds the image when the pin files
change (Rafelo lesson v0.19.0). `bin/ci` runs the same inside the
container and in GitHub CI.

Rule format, statuses and precedence follow Rafelo
(`~/personal/projects/rafelo/docs/architecture/`): a rule is enforced
only with a CI tool and a canary, otherwise review. The pack-versus-project
table is built against the vendored OO pack version.

## State

- Milestone v0.3.0 (tooling and pilot) is open.
- #11 (lead): this control plane.
- Planned implementer issues in v0.3.0: Markdown lint with mise and
  Node; OO pack v1.0.1; the `lead_guard` canary in `bin/ci`; the loop
  driver and systemd units.

## Next steps

1. Merge #11, then file and dispatch the v0.3.0 implementer issues.
2. Prove the loop on one issue from this interactive session; record the
   metrics (protocol §12).
3. Install the driver, update my-notes, and let the loop run.
4. v0.4.0: draft the specification files in this order: 00, 13, 01, 02,
   03, 04, 05, then the rest; the implementer builds `docs:check`.

## Open questions

- How a headless `claude -p` run learns the remaining weekly budget (the
  status line file is not written in headless mode). The driver issue
  settles it.
