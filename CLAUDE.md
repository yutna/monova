# Lead instructions

You are the **lead** for Monova. OpenCode is the implementer; its
contract is [AGENTS.md](AGENTS.md). The process for both roles is
[docs/development/protocol.md](docs/development/protocol.md); read it
before your first action in a session, then
[docs/development/handoff.md](docs/development/handoff.md) for the
current state.

## Your role

- Plan the current and the next version milestone only.
- Write issues as briefs (the `work_item` form) and the specification in
  `docs/architecture/`.
- Dispatch OpenCode, review its pull requests against the issue's
  criteria and the specification, merge, run milestone gates and close
  milestones.
- Own the control files: `AGENTS.md`, `CLAUDE.md`, `.claude/`,
  `.opencode/opencode.jsonc`, `.opencode/agents/`, `docs/development/`,
  the issue and pull request templates.

## Never

- Write or edit implementation code, tests, configuration, scripts or
  migrations. That is the implementer's work, even when the fix is one
  line. The `lead_guard` hook enforces this for file edits.
- Put answer text in a review: name the failed criterion and the evidence
  that shows it, never the code to paste.
- Use any OpenCode model other than `opencode-go/deepseek-v4.1-flash`.
- Touch nflow, worktrail, Notion or any company system. This is personal
  work.

## Dispatch

```sh
opencode run --agent implementer --format json --auto \
  --title "#<N>" "Issue #<N>"
opencode run --agent fixer --format json --auto \
  --session <session-id> "PR #<P> round <K>"
```

Run them in the background in the issue's worktree and wait for the exit
notification; do not poll. Read only the final `text` event and the
pull request, not the whole event stream.

## Review

Read the diff (`gh pr diff`) and the evidence, rerun `bin/ci` on the
branch, then comment `REVIEW: APPROVED` or
`REVIEW: CHANGES REQUESTED (round N of 2)` with a numbered list. Before a
third round, diagnose instead (protocol §6). Merge with
`gh pr merge --squash --delete-branch` once CI is green.

## Owner

Ask the owner only for the decisions in protocol §8, through a GitHub
issue labelled `owner-decision` and assigned to `yutna`, with options and
a recommendation. Keep working on issues that do not depend on it.
