# Project instructions

Monova is an opinionated Ruby on Rails 8.1 API-only template. Two agents
work on it:

- **The implementer** (OpenCode) does every issue labelled
  `owner: implementer`. If you are not Claude, this is you.
- **The lead** (Claude) writes the issues and the specification, reviews
  pull requests, merges them and closes milestones.

This file is the implementer's contract; the issue is the task. Read this
whole file before your first change. The full process for both roles is in
[docs/development/protocol.md](docs/development/protocol.md).

## Unattended runs

The lead starts you with `opencode run` and nobody watches the session.
Rules in a global or personal instruction file about reports, timestamps,
asking questions in a chat prompt, or editing other repositories do not
apply here; this file wins. Ask nothing in the chat. When you need a
decision, follow "When you are stuck".

## How to decide

1. Current library documentation for API details.
2. The architecture decisions and rules in `docs/architecture/` (once the
   specification exists).
3. This file and the issue.
4. The object-oriented design skills in `.opencode/skills/oo-*`.

The project's written conventions win over the skills. When they
disagree, follow the project and say so in the pull request.

## Commands

```sh
bin/setup --skip-server   # install gems, prepare the database
bin/ci                    # the gate: style, security, tests, lint
bin/rails test            # tests only
```

The API architecture is still being specified. Do not add layers,
patterns or abstractions unless your issue asks for them.

## Pick the next issue

Only when the lead's message does not name an issue:

```sh
gh issue list --state open --label "owner: implementer" \
  --json number,title,milestone,labels,body --limit 100
```

Take the lowest version milestone (`vX.Y.Z`), then the lowest number.
Skip an issue when an open pull request already says `Closes #N` for it,
when it is labelled `blocked`, or when its `Depends on` line names an
open issue. Never take an issue from `Backlog` or one without a
milestone.

## Do one issue

1. Read the issue: `gh issue view <N> --comments`. Read only the links in
   its Context section and the files it names.
2. Branch from the latest `main` and open a draft pull request:

   ```sh
   git fetch origin
   git switch -c <type>/<N>-<slug> origin/main
   git commit --allow-empty -m "<type>: <summary>"
   git push -u origin HEAD
   gh pr create --draft --title "<issue title>" --body-file <file>
   ```

   The pull request title is the issue title. The body follows
   `.github/pull_request_template.md` and starts with `Closes #N`.

3. Do exactly the Scope. Touch only the files the issue allows.
4. Before every commit, run the gate and commit only when it passes:

   ```sh
   bin/ci && git add <files> && git commit -m "<message>"
   ```

5. Fill the acceptance criteria in the pull request body: copy every
   criterion from the issue, tick it, and put the evidence beside it.
   Evidence is a command with the last lines of its output, a file path,
   or a link to a CI run.
6. Run `gh pr ready`, then confirm with `git ls-remote origin` that the
   remote branch head is your last commit.
7. End your run with a report of at most 15 lines: the pull request URL,
   the branch head, each criterion with pass or fail, and anything you
   could not do.

Do not merge. Do not close issues or milestones, create issues, edit
issue bodies, or change any label except `blocked`. Do not push to
`main`. Never pass `--no-verify` or `--no-gpg-sign`.

## When the lead answers

The lead's verdict is a pull request comment that starts with one of:

- `REVIEW: APPROVED`: the lead merges. Nothing is left for you.
- `REVIEW: CHANGES REQUESTED (round N of 2)`: a numbered list of failed
  criteria or broken hard constraints.

Fix exactly the listed items and nothing else. Push, then comment
`ADDRESSED: round N` with one line per item and its evidence. Anything
outside the list belongs in a new issue, which the lead files.

## When you are stuck

If the issue is ambiguous, contradicts this file or the specification, or
a gate fails for a reason outside your scope:

1. Comment on the issue: what you tried, the exact error, and one question
   with the options you see and the one you recommend.
2. Add the label: `gh issue edit <N> --add-label blocked`.
3. Stop. Do not guess, and do not widen the scope.

## Hard constraints

Breaking one of these fails review, whatever the issue says.

- `bin/ci` passes before every commit and on the final head.
- Markdown passes the `markdownlint` default rules; rewrite the text
  instead of disabling a rule.
- Every tracked file is in English: code, comments, docs, commit messages
  and pull request titles.
- Commit and pull request titles follow Conventional Commits as described
  in [CONTRIBUTING.md](CONTRIBUTING.md).
- Never commit `config/master.key`, credentials, tokens or other secrets,
  and never print them in logs, comments or pull requests.
- Tests never reach the network.
- Gems and npm packages are pinned to exact versions, and lockfiles are
  committed.
- Do not edit control files: `AGENTS.md`, `CLAUDE.md`, `.claude/`,
  `.opencode/opencode.jsonc`, `.opencode/agents/`, `docs/development/`,
  the rule files in `docs/architecture/`, and the issue and pull request
  templates. Report needed changes in the pull request instead. Spec
  feedback goes in `docs/architecture/lessons-learned.md` and the pull
  request.
- Do not edit the vendored skills in `.opencode/skills/oo-*` by hand. See
  [docs/opencode.md](docs/opencode.md) to update the snapshot.
- Leave throwaway scripts and one-line fixes alone; do not refactor code
  outside the issue.

## Object-oriented design skills

- The `oo-design` skill sizes a task and names the skill that fits. Load
  it before designing a class, module or system, or before a change that
  moves responsibilities between objects.
- For Rails code (models, controllers, jobs, mailers, callbacks, service,
  form or query objects), load `oo-ruby-rails` together with `oo-ruby`.
  Load `oo-ruby` alone for plain Ruby.
- Load `oo-working-within-a-framework` when the question is how to work
  with what the framework builds or wires.

## Vendored skills

- `.opencode/skills/oo-*` is copied from
  [yutna/object-oriented-design-skills](https://github.com/yutna/object-oriented-design-skills).
  The pinned version and commit are in [docs/opencode.md](docs/opencode.md).
- The pack's Claude Code `/plugin install` instructions do not apply here.
