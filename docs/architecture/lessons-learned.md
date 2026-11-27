# Lessons learned

This file records what surprised the lead or the implementer, the root
cause, what changed, and feedback on the specification, the protocol or
the object-oriented design skills. It cites rule IDs; it never defines a
rule.

## 2026-11-26 — v0.3.0 — #11 (control plane)

**What happened.** Four OpenCode 2.2.6 behaviours differed from what the
plan assumed:

1. `opencode run "/command args"` does not expand a project command; the
   model receives the text and goes looking for the file.
2. `OPENCODE_CONFIG` and `OPENCODE_CONFIG_DIR` are not read
   (`opencode debug config` lists no such source), so a worktree based
   on `main` cannot borrow the new policies before they merge.
3. The global `~/.config/opencode/AGENTS.md` (the owner's interactive
   rules) is loaded into unattended runs; a probe run opened its report
   with a Thai timestamp.
4. The `lead_guard` shell check matches a write command and an
   implementation path anywhere in the same command, so it blocked an
   issue body that mentioned a Bundler command, and a `sed -i` on a file
   outside the repository that ran in the same command as `bin/ci`.

**Root cause.** The plan was written from the documentation, which does
not list the `run` flags or the environment overrides, before a probe
ran. The shell check reads command text, not parsed arguments.

**What changed.** The protocol lives in the agent prompts and the
dispatch message is one line (`Issue #N`). The first implementer issue
ran in a worktree with the control files laid over `main` as uncommitted
files, and the message told the implementer never to stage them.
`AGENTS.md` says that global rules about reports and questions do not
apply to unattended runs. The lead writes issue bodies and other text
with the Write tool, and keeps a guard-tripping command separate from
the rest.

**Protocol feedback.** §5 should say that control-plane changes merge
before any issue that depends on their guards is dispatched. The shell
check stays "enforced" only for the probed cases; anything else is
review (§10).

## 2026-11-26 — v0.3.0 — #13, #15, #16 (pilot issues)

**What happened.** Three implementer issues ran through the loop with
zero review rounds. Each stopped correctly once at a boundary instead of
guessing: #13 found a Ruby CVE outside its scope, #15 found lint errors
in a lead-owned file it may not edit. Three acceptance criteria written
by the lead could not pass: `ruby -v` resolved the host's global mise
pin, `opencode debug` is denied by the implementer's own policy, and the
lint gate failed on the lead's control files.

**Root cause.** The lead wrote criteria without running them under the
implementer's environment and policies, and turned on a gate before its
own files met it.

**What changed.** Before filing an issue, the lead runs each evidence
command it can under the same policies, or words the criterion so the
implementer can run it. A gate is enabled only after the lead's files
pass it (#27 before #15).

**Metrics.** Wall time 3 to 7 minutes per implementer run; tokens per
issue 47k to 100k input, 7k to 16k output, 1M to 5M cache read; defects
found in review: 0 blocking.

**Protocol feedback.** §4 could require that every criterion is
runnable by the implementer under its policies.

## 2026-11-26 — v0.3.0 — loop installation

**What happened.** Three traps showed up before the first unattended
tick. A process started with `nohup setsid` inside the driver's oneshot
systemd unit was killed when the unit ended, so a detached implementer
would have died with every lead run. Milestone `v0.2.1` was open with
all its issues closed, so the rule "the lowest open milestone with every
issue closed is complete" would have gated and released it. The headless
lead loads the owner's global `~/.claude/CLAUDE.md`, which asks for
choice prompts, timestamps and new-session suggestions.

**Root cause.** The dispatch was only ever tested from an interactive
session, whose background jobs live outside any service cgroup. The
milestone rule did not say which milestones belong to the loop. Global
instructions assume a person in the chat.

**What changed.** The lead dispatches OpenCode as its own transient unit
with `systemd-run --user` (passing `PATH` and `HOME`) and records its
`MainPID`; a probe proved it outlives the driver. The loop prompt limits
the lead to milestones from `v0.3.0` on, says a milestone with no issues
is never complete, and overrides the chat-only global rules; #54 also
denies `AskUserQuestion` in the driver. A headless probe proved that
`lead_guard` blocks a Write under `app/`.

**First ticks.** Tick 1 ran the v0.3.0 gate in a fresh subagent, which
found that protocol §10 claimed the GitHub ruleset as enforced without a
check (#57), and filed three follow-ups (one duplicate of #28, closed).
Tick 2 dispatched #57. Cost per lead tick: USD 0.30 to 1.20.

## 2026-11-27 — v0.5.0 — milestone gate

**What happened.** The gate passed, with three process findings. The
host has no PostgreSQL 18 client, so `bin/ci` on a clean checkout
needed a `psql` and `pg_dump` shim taken from the pinned image. The
metrics in the final review comments used different formats from one
pull request to the next, which made the gate's summary slow. Handoff
PR #126 changed a control file without the `owner: lead` label.

**Root cause.** The README assumes host clients that only the Dev
Container provides. Protocol §12 lists the metrics but not one layout.
The lead labels its own pull requests by hand.

**What changed.** The lead writes every final review comment with one
metrics block: wall time, rounds, session tokens (input, output, cache
read), defects. Every lead pull request gets `owner: lead` when it is
opened.

**Metrics.** 12 implementer pull requests: 10 approved on the first
pass, 2 change rounds in total, 3 defects found in review; about 166
minutes of implementer wall time (median about 10.5); about 40M tokens
with cache.

**Protocol feedback.** §12 could fix the metrics layout. Whether the
host loop should install a PostgreSQL 18 client or always run `bin/ci`
in the Dev Container is open for v0.6.0 planning.

## 2026-11-28 — v0.8.0 — #166 (finding admission, from Rafelo)

**What happened.** Rafelo reported (at the owner's request) that its AI
gate audits stopped converging: in about 27 hours its round 3 closed 13
of 124 issues while the gates filed 26 new S3 findings, most of them
edge cases in hand-written parsers for small languages. Monova's gates
showed the start of the same pattern: the v0.7.0 gate and its follow-up
drew three findings on one shell guard, `packwerk_check`: #153, #154
and #158.

**Root cause.** Taken from Rafelo's entry of 2026-11-28 and applied
here. The protocol did not define S1, S2 or S3 and did not ask for a
failure scenario, so any edge case an auditor could imagine became an
issue. No threat model said whom a guard defends against. A
hand-written text matcher has an unbounded input space. A fix that
patches the reported string leaves the neighbouring case for the next
audit. And the layers recurse: guards check code, canaries check
guards, gates check canaries.

**What changed.** Protocol §7 gained a finding admission rule: a
four-part failure scenario, severity by impact, a threat model per
surface (adversarial for the runtime that ships to adopters, honest
mistakes for tooling), a fix per input class, parser replacement on a
second same-class finding, a redesign after three rounds, no silent
S1 or S2 downgrade, and a count of findings per component. §6 says how
its two-round limit and the redesign trigger differ. The loop prompt
tells the gate subagent to apply the rule.

**Spec feedback.** None. The rule stays in the protocol, not in
`docs/architecture/`, because an adopted copy keeps the specification
but not the template's own process (ADR-01).
