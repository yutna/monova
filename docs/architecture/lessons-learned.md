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
