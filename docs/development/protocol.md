# Development protocol

This is how the Monova template repository itself is built. It is the
template's own process, not a rule for applications made from the
template; the specification's workflow file says what adopters keep.

## 1. Roles

| Role | Who | Does |
| --- | --- | --- |
| Lead | Claude Code | Plans, briefs, specifies, reviews, merges |
| Implementer | OpenCode | Implements one issue per pull request |
| Gate | Fresh Claude run | Audits a milestone before it closes |
| Owner | yutna | Decides only what §8 lists |

The lead never writes implementation code. The implementer never edits
control files, merges, or plans work. The gate has no context from the
lead's runs, so it can disagree with them.

The implementer uses only `opencode-go/deepseek-v4.1-flash` (the
subscription model), pinned in `.opencode/opencode.jsonc` and in each
agent. A free model is never used.

## 2. Sources of truth

1. Current library documentation for API details.
2. ADRs, then rules, in `docs/architecture/`.
3. This protocol, `AGENTS.md` and `CLAUDE.md`.
4. The issue.
5. The object-oriented design skills.

GitHub (issues, pull requests, milestones) and `git log` hold the state.
The handoff note summarises it for a new session; when they disagree,
GitHub wins.

## 3. Who edits what

| Files | Edited by |
| --- | --- |
| Rule files and ADRs in `docs/architecture/` | Lead |
| `docs/architecture/lessons-learned.md` | Lead and implementer |
| `docs/development/` | Lead |
| `AGENTS.md`, `CLAUDE.md`, `.claude/` | Lead |
| `.opencode/opencode.jsonc`, `.opencode/agents/` | Lead |
| Issue and pull request templates | Lead |
| Everything else | Implementer |

A pull request that changes a control file is labelled `owner: lead`
and is written by the lead. A change to a guard (a CI step, a check
script, a canary) inside a feature pull request is a guard change: the
lead reviews it as one and says so in the review.

## 4. Milestones and issues

- Only the current and the next version milestone are planned. A finding
  outside an issue's criteria becomes an issue in the next milestone or
  in `Backlog`, never in the current one.
- A milestone's scope freezes when its first pull request merges.
- Every implementer issue uses the `work_item` form: goal, context links,
  scope, non-goals, files, rule IDs, acceptance criteria with the command
  that proves each one, `Depends on`.
- An issue is small enough for one pull request and one implementer
  session. A bigger one is split before dispatch.
- Every criterion is runnable by the implementer under its policies and
  environment; the lead runs the ones it can before filing. A new gate
  is enabled only after the lead's own files pass it.

## 5. The loop

1. The driver (`script/loop/`, a systemd user timer) checks the budget
   (§9) and starts one fresh headless lead run when no run is active.
2. The lead follows [loop_prompt.md](loop_prompt.md): it finds the next
   action (a pull request to review, a ready issue to dispatch, a
   milestone to plan or close) and does exactly one of them.
3. Dispatch: in a git worktree for the issue, the lead starts
   `opencode run --agent implementer --format json --auto` with the
   message `Issue #N` as a transient systemd user unit
   (`systemd-run --user`), so it outlives the lead run. The lead writes
   the unit's main process ID to the loop's `implementer.pid` and ends
   the run. Control-plane changes merge before any issue that relies on
   their guards is dispatched.
4. A later run reviews the pull request (§6). Approved: the lead merges
   with `gh pr merge --squash --delete-branch` once CI is green.
5. The lead records the result: the handoff note when the state changed,
   `lessons-learned.md` when something surprised it, the metrics (§12).
6. The run ends. The next timer tick starts a fresh run, so no run carries
   a long context.

## 6. Review rounds

- The lead reviews only the issue's criteria, the hard constraints in
  `AGENTS.md`, and the rules the issue cites. It reads the diff and the
  evidence, not whole files, and reruns `bin/ci` on the branch.
- A wrong fact, a failed criterion or a broken constraint must be fixed.
  Taste and wording become new issues.
- The verdict is a comment: `REVIEW: APPROVED`, or
  `REVIEW: CHANGES REQUESTED (round N of 2)` with a numbered list of
  failed criteria and their evidence. It never contains code or text for
  the implementer to paste.
- Fixes go back with `opencode run --agent fixer --session <id>`.
- At most two change rounds. Before a third, diagnose from the issue, the
  session's final report and the task's size. An ambiguous, wrong or too
  big issue is rewritten or split. A clear issue gets a different way of
  working: a fresh session, one item at a time, or a failing check that
  shows the defect. Record the diagnosis in `lessons-learned.md`.
- The two-round limit counts rounds inside one pull request. The
  redesign trigger in §7 counts findings on one component across pull
  requests and gates. Each limit applies on its own.
- A review finding outside the issue's criteria follows the admission
  rule in §7 before it becomes a new issue.

## 7. Milestone gate and release

When every issue in a milestone is closed:

1. A fresh Claude run with no lead context audits the milestone: the
   issues' criteria against `main`, the rules the milestone touched, the
   enforcement claims (a rule marked enforced has a CI tool and a canary),
   and `bin/ci` on a clean checkout. It applies the finding admission
   rule below to everything it reports.
2. Blocking findings (S1 and S2) become issues in the same milestone,
   and the loop continues. S3 findings go to the next milestone or to
   `Backlog`.
   An issue closed as not planned (a duplicate or a dropped item) counts
   as closed, provided a comment on it links the issue or pull request
   that covers it, or says why it was dropped.
3. When the gate passes, the lead updates `VERSION` through a pull
   request and closes the milestone, which publishes the release.

### Finding admission

A gate converges only when it files findings that someone will hit.
Quality here means no failure that a real user meets, weighted by harm;
it does not mean no findings. These rules decide what a finding is and
how much it counts.

- **Failure scenario.** Every finding names four things: the actor, the
  input or action, the wrong result, and who is hurt (an adopter's API
  in production, an adopter's developer or AI agent, or this
  repository's CI). A finding with no reachable scenario is a note in the
  gate report, not an issue.
- **Threat model per surface.**
  - Runtime code that ships in an adopter's API (the AUTH, DATA, SEC and
    API rules: tenancy and RLS, tokens and scopes, BOLA, input handling)
    keeps the full adversarial model: an attacker sends any input.
  - Tooling (`bin/ci`, `script/`, canaries, generators, the OpenCode
    policies and the `lead_guard` hook) guards against honest mistakes
    and shortcuts by a developer or an AI agent: ordinary syntax,
    ordinary encodings, the tool's documented configuration. An input
    built only to slip past a guard (escapes, odd whitespace or
    delimiters, Unicode tricks) is S3 at most, unless a rule in
    `08_security.md` names that evasion.
- **Severity follows impact.**
  - S1: a security hole or data loss in an adopter's production API (a
    cross-tenant read or write, a token or secret leak, a bypassed
    policy), or a guard that lets a rule violation merge unnoticed in
    normal use.
  - S2: a MUST rule not met in a way an adopter or their agent meets in
    normal use, or a guard that wrongly blocks valid work.
  - S3: everything else: hardening, wording, and inputs that only a
    deliberate attempt would produce against tooling.
- **No silent downgrade.** A filed S1 or S2 keeps its severity unless a
  comment on its issue states the failure scenario that justifies the
  lower one.
- **Fix the class.** A finding about input handling names its input
  class. The fix covers the class, with a canary per class, not only the
  reported string.
- **Replace hand-written parsers.** When a hand-written parser or
  matcher (shell text matching, a regular expression over a file format)
  draws a second finding of the same class, the next pull request
  replaces it with the tool's own parser or output format, an AST, or a
  library already in the stack.
- **Redesign after three rounds.** When one component draws findings in
  three consecutive fix rounds, or in two gates in a row, stop patching:
  the next pull request redesigns it from its rule, and the gate report
  says why.
- **Count per component.** The gate report lists the number of findings
  per component, so a loop is visible across gates.

These rules are the template's own process, like the rest of this
protocol, so they live here and not in the specification: an adopted
copy keeps the specification but not this process (ADR-01, ADR-10 to
ADR-14).

## 8. Owner decisions

The lead asks the owner only for:

- secrets, credentials, accounts and paid services;
- actions outside this repository that cannot be undone;
- a contradiction between ADRs or principles that the specification
  cannot settle;
- loosening a guard when the lead and the gate disagree;
- a change to this list.

The lead opens an issue labelled `owner-decision`, assigned to `yutna`,
with the context, the options, what each one changes, and a
recommendation. The loop keeps working on everything that does not depend
on it. Everything else (architecture details, library choice, best
practice) the lead decides and records in an ADR or the pull request.

## 9. Budget

- The driver stops starting runs when the personal account's weekly
  usage reaches 95%, and resumes after the weekly reset.
- On a five-hour limit, the driver waits for that window's reset.
- The driver reads both from the `rate_limit_event` that every headless
  run emits with `--output-format stream-json`.
- Tokens are spent carefully: one action per run, diffs instead of whole
  files, the final report instead of the whole event stream, and briefs
  that name the files to read.

## 10. Guards on the process

| Guard | Enforced by | Status |
| --- | --- | --- |
| Implementer cannot push to `main` or merge | OpenCode `policies` | enforced |
| Implementer cannot edit control files | OpenCode `policies` | enforced |
| Implementer cannot read secrets | OpenCode `policies` | enforced |
| `main` takes only squash merges with CI | `ruleset_check` | enforced |
| Lead edits only control files and docs | `lead_guard` hook | enforced |
| Shell writes that bypass the edit tools | Lead and gate review | review |
| Review never contains answer text | Gate review | review |

The OpenCode policies cover the edit and read tools and the listed shell
commands; a shell redirect can still write a file, so the review checks
that the diff touches only allowed paths. Every guard marked enforced has
a canary that proves it fails when it should.
The `lead_guard` hook runs only while the project settings are in
effect: an uncommitted `.claude/settings.local.json` can turn it off,
and CI cannot see that file, so the gate still reads the lead's diffs.
The `main` ruleset lives in GitHub; `script/ci/ruleset_check` reads it
in CI and fails when it drifts, and its `--canary` mode is the canary.

## 11. Lessons and feedback

- `docs/architecture/lessons-learned.md` records what surprised the
  lead or the implementer: what happened, the root cause, what changed,
  and feedback on the specification or this protocol.
- Feedback on the object-oriented design skills is collected there with
  the skill name and rule, and filed upstream as an issue in
  `yutna/object-oriented-design-skills` once per milestone.

## 12. Metrics

For each implementer issue the lead records in the pull request's final
comment: the implementer's wall time, the number of review rounds, the
tokens of the implementer session (from its `step_finish` events), and
the defects the review found. A lead pull request has no implementer
session, so it records no metrics. The gate summarises them per
milestone.
