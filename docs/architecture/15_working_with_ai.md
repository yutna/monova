# 15 — Working with AI

Which AI instruction files an adopted Monova ships, what goes in each,
and how a team runs an AI lead and an AI implementer on them. Tools
guard, people decide, AI builds (ADR-19): an instruction file helps an
agent reach a green `bin/ci` on the first try, and it never replaces a
guard (`00_README.md`, Enforcement statuses). The template's own build
files are not these files and do not survive adoption (WF-01).

## Terms

| Term | Meaning |
| --- | --- |
| Root guide | `AGENTS.md` at the repository root |
| Engine guide | `engines/<engine>/AGENTS.md`, written by a generator (GEN-05) |
| Task skill | `.opencode/skills/<name>/SKILL.md` for one recurring task |
| Design pack | The `oo-*` skills, a pinned copy of an outside pack |
| AI file | Any of the above, and `CLAUDE.md` |

## Rules

### AI-01 — AI files cite rules and never restate them (MUST · ADR-19)

- An AI file names a rule by its ID (`DOM-04`) and an ADR by its number.
  A copy of a rule's text drifts when the rule changes; an ID does not.
- An AI file holds no "make sure X". When X can be checked, a tool
  checks it and its message names the rule; when it cannot, a person
  reviews it.
- An AI file holds no fact kept elsewhere: no version number
  (`00_README.md`, Runtimes), no copy of a generated file or schema, no
  secret, no real personal data (DATA-13).
- An AI file never tells an agent to loosen a guard: no disable comment,
  no budget raise, no todo file (ARCH-05), no skipped `bin/ci` step
  (WF-02).
- `npm run docs:check` fails when an AI file it reads cites an ID that
  does not exist or a superseded ADR. Every AI file is in its list.

### AI-02 — The root guide is short and loaded in every session (SHOULD · ADR-19)

The root guide is read at the start of every session, so each line
costs attention on every task. A person reads it in two minutes;
anything longer moves into a skill. It has these sections, in order:

```markdown
# AGENTS.md — <app name>
## What this app is          <!-- three lines: purpose, clients, engines -->
## Commands                  <!-- bin/setup, bin/rspec, bin/ci, generators -->
## How to decide             <!-- the precedence of 00_README.md -->
## Rules you will touch most <!-- IDs and a few words each -->
## Pack versus project       <!-- AI-07 -->
## Never                     <!-- includes: never loosen a guard -->
## Skills                    <!-- where task skills and the pack live -->
## Definition of done        <!-- bin/ci green, criteria with evidence -->
```

The template ships its own build contract as `AGENTS.md`. At adoption
(`00_README.md`, step 6) the adopter replaces it with a root guide of
this shape.

### AI-03 — An engine guide adds only what is special to its engine (MUST · ADR-08)

- GEN-05 says what an engine guide contains. It never repeats the root
  guide and never gives guidance for another engine kind (ARCH-02).
- The root guide tells the agent to read an engine's guide before it
  changes that engine. OpenCode and Claude Code load a nested
  `AGENTS.md` on demand, when the agent reads a file in that folder;
  the instruction makes it happen before the first edit, not after.
- Product engines' guides look alike, as do domain engines'. When one
  is improved, the generator's template is improved with it, so new
  engines start from the better guide (GEN-08).

### AI-04 — Each recurring task has one skill (SHOULD · ADR-19)

The template ships these task skills:

| Skill | Starts from |
| --- | --- |
| `add-domain-engine` | `core:domain_engine` (GEN-03) |
| `add-product-engine` | `core:product_engine` (GEN-04) |
| `add-endpoint` | `core:endpoint` (GEN-06), then DOM-04 or DOM-07 |
| `publish-event` | DOM-09, DOM-10, DOM-11 |
| `add-job` | INT-01 to INT-04 |
| `fix-failing-guard` | The guard's message, which names the rule (AI-05) |

- A skill has a `name` equal to its folder name, in lowercase
  kebab-case, and a `description` that starts with "Use when". The
  description decides when an agent loads it.
- Its body: the inputs to collect, the generator command, the files left
  to fill in order, the rule IDs that apply, the check commands, and
  when it is done. It never repeats a step the generator already does.

### AI-05 — A failing guard is fixed in the code, never in the guard (MUST · ADR-19)

- The agent reads the guard's message, fixes the code and runs the check
  again. It never edits the guard, its canary, its fixtures, a budget
  or a row of `12_enforcement.md`.
- When the guard looks wrong, the agent stops and writes the proposed
  guard change into the pull request description for a person, who
  decides it in a pull request of its own (`12_enforcement.md`,
  Moving a row).
- The root guide's "Never" list carries this rule's ID.

### AI-06 — The design pack is a pinned, unmodified copy (MUST · ADR-01)

- `.opencode/skills/oo-*` is
  [object-oriented-design-skills](https://github.com/yutna/object-oriented-design-skills)
  v1.0.1, copied without change. `THIRD_PARTY_NOTICES.md` records its
  license, release and commit.
- Nobody edits a pack file. Updating the pack replaces the whole
  snapshot and the notice in one pull request, which rechecks the table
  of AI-07 against the new release.
- The pack is general advice, the last source in the precedence of
  `00_README.md`. Its skills cite no rule IDs, so `docs:check` does not
  read them.

### AI-07 — The root guide maps the pack onto the project (MUST · ADR-09)

The pack assumes a domain model that owns its rules and stores
aggregates through repositories. Monova keeps logic in plain objects
around Active Record (ADR-09), so the root guide has a "Pack versus
project" section with one row for each place they disagree:

- `oo-designing-repositories`: no repository classes; models and
  queries (ADR-09, DOM-07).
- `oo-designing-aggregates`: a command's unit of work is the tenancy
  transaction (DOM-04, DOM-05).
- `oo-layering-the-system`: three engine kinds and one home per kind of
  logic (ARCH-02, DOM-01).
- `oo-inverting-dependencies`: commands and queries use Active Record
  directly; a port only at an outside service (DOM-01, INT-08).
- `oo-separating-reads-from-writes`: queries read through the caller's
  scope; no separate read store (DOM-07).
- `oo-bounding-contexts`, `oo-organising-modules`: engines and their
  declared graph (ARCH-02, ARCH-04, ARCH-06).
- `oo-separating-presentation-from-domain`: API only; serializers shape
  the JSON (API-02, PERF-03).
- `oo-publishing-domain-events`: events leave through the outbox
  (DOM-09, DOM-10).

The section also names the pack's entry points: `oo-design` for sizing a
design, `oo-ruby-rails` for models, callbacks, commands and queries,
`oo-working-within-a-framework` for what Rails builds, and
`oo-reviewing-object-design` for review, which assists a person only.
When an agent finds the pack and a rule disagreeing, it follows the rule
and says so in its pull request.

### AI-08 — One copy of each instruction, read by every tool (SHOULD · ADR-19)

- OpenCode reads the root `AGENTS.md` at startup and discovers skills in
  `.opencode/skills/`, and also in `.claude/skills/` and
  `.agents/skills/`. A skill without a `description` is not offered.
- Claude Code reads `AGENTS.md` only when there is no `CLAUDE.md`. A
  project with a `CLAUDE.md` puts the line `@AGENTS.md` in it, so the
  root guide stays the one source. Claude Code finds skills only in
  `.claude/skills/`, so that folder links to `.opencode/skills/`
  instead of holding copies.
- These facts were checked against the OpenCode and Claude Code
  documentation on 2026-11-26. Check again when changing tools.

### AI-09 — A person approves every AI file change, after a trial (SHOULD · ADR-19)

- An AI may draft an AI file. A person reviews it in an ordinary pull
  request, checking that it cites and does not restate (AI-01).
- Before the change merges, a few representative requests run in a
  fresh session, which sees only what the files give it: a new
  endpoint, a new engine, an event, a request that tempts the agent to
  loosen a guard, and one that needs a person's decision. The pull
  request records for each whether the first push passed `bin/ci`
  unedited, the questions the files should have answered, how each
  guard failure was fixed, and any file touched outside the task.
- A failed trial changes the AI file or the generator, then runs again
  in a new session. The guard stays as it is.
- AI files are updated when a rule, an ADR or a generator changes, and
  when real pull requests repeat the same mistake.

## Running a lead and an implementer

A team may split the AI work in two, as the template's build does. The
roles, not that build's loop, are what carry over:

- **Lead** (for example Claude Code) reads the specification and the
  ADRs, writes issues whose criteria each name a proving command,
  reviews diffs and reruns `bin/ci`. It never writes the implementation
  and its review never counts as a guard.
- **Implementer** (for example OpenCode) reads the root guide, the
  engine guide and one issue, and opens one pull request with evidence
  for each criterion. It never edits AI files, guards or the
  specification, and never merges.
- **People** approve guard, ADR and AI file changes and merge. They
  never hand a decision to an AI.

- The implementer's tool is fenced by its own permission settings, so
  it cannot push to `main` or merge. The `main` ruleset (WF-03) holds
  whatever the settings miss.
- A hook in the lead's tool is a fence, not a guard. A local settings
  file that is not committed (Claude Code's
  `.claude/settings.local.json`) can turn hooks off or override them,
  and CI cannot see it, so the review still checks every diff.
- A review names the failed criterion and its evidence, never code to
  paste, so the implementer fixes the cause.
- Each pull request records the session, its model and its cost, so the
  team sees what an issue size costs.
