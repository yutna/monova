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
Node 26.13.1 (latest LTS) and Ruby 4.0.10 pinned in `mise.toml`.

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

## Differences from Rafelo's way of working

| Topic | Rafelo | Monova |
| --- | --- | --- |
| Who drives OpenCode | Cron supervisor | Fresh headless lead run |
| Review | Owner-triggered rounds | Every PR, then a milestone gate |
| Merge and release | Owner | Lead, after CI and the gate |
| Spec | Written before the build | Drafted by the lead in v0.4.0 |
| Protocol for OpenCode | Long continue prompt | Agent prompts, `Issue #N` |
| OpenCode fence | Instructions only | `policies` hard denies, probed |
| Lead fence | None | `lead_guard` hook |
| Delivery | `rails new -m`, kernel update | Template copy-and-own |
| Build loop host | Host, mise, Postgres container | Same, own container |
| Adopter environment | Dev Container | Dev Container, proven in CI |
| GitHub identity | Machine user planned | Owner's account for both roles |

The build loop runs on the host, like Rafelo's: Ruby and Node from
`mise.toml`, and a PostgreSQL container pinned by version and digest,
named `monova-postgres` on `127.0.0.1:5433` (5432 belongs to
`rafelo-postgres`). Adopters get a Dev Container, and a CI job builds it
and runs `bin/ci` inside it so it cannot rot. Because both roles use the
owner's GitHub account, a GitHub approval cannot separate them; the
`REVIEW:` comment is the verdict, as in the OO-skills repository.

## State

- v0.3.0 through v0.7.0 are gated, released and closed (`VERSION` is
  0.7.0, #160). v0.7.0 added the `core` kernel engine and Packwerk; its
  gate findings #153 and #154 merged as #155 and #156.
- v0.8.0 (AUTH and DATA on top of core) is open. Merged so far: #158
  (Packwerk's singular file count, #165), #161 (strong_migrations and
  its canary, #167) and #166 (the finding admission rule in protocol
  §7, #168). Open, in order: #162 (core's base record, table defaults
  and `core_tenants`) is with the implementer, draft PR #169; #163 (the
  per-transaction tenancy helper) and #164 (the tenant policy helper,
  `TenantOwned` and the DATA-03 catalog check) wait for it.
- The loop driver is installed as the `monova-loop` systemd user timer
  (from 2026-11-26); see my-notes
  `manuals/asus-nuc-server/13-monova-loop.md`.

## Next steps

1. Review PR #169 (#162) once its implementer run has ended, and merge
   it.
2. Dispatch #163, then #164, as their dependencies close.
3. When every v0.8.0 issue is closed, run the gate with a fresh
   subagent that applies the finding admission rule; when it passes,
   bump `VERSION` to 0.8.0 through an implementer issue and close the
   milestone.
4. Plan v0.9.0 from the specification once v0.8.0 is under way; never
   plan further ahead.

## After the major release

The owner decided (2026-11-26): only when both Monova and Rafelo are
finished (both released, no loop, supervisor or open work running, and
the only remaining input is feedback from people using the templates),
the lead runs a retrospective of both repositories' lessons and ways of
working, then Rafelo changes to work the way Monova does. Either one may
finish first; wait for the other. The lessons
also feed Mycelia. Until then, keep every process lesson in
`docs/architecture/lessons-learned.md` so the retrospective has its
material.

## Open questions

- None. (Settled: a headless `claude -p --output-format stream-json
  --verbose` run emits a `rate_limit_event` with the five-hour and
  seven-day utilization and reset times; the driver records it.)
