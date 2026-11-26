# 14 — Workflow

How changes reach `main` and become releases. The template repository is
built by its own process (ADR-10 to ADR-14); an adopted copy keeps the
gate, the release flow and the dependency rules, not that process
(ADR-01). One gate decides what merges (ADR-19), and dependencies change
one reviewed pull request at a time (ADR-16).

## Terms

| Term | Meaning |
| --- | --- |
| Template build | The process that builds Monova, in `docs/development/` |
| Gate | `bin/ci`, the one command whose steps decide a merge |
| Version milestone | A GitHub milestone titled `vX.Y.Z` |
| Peer group | Packages that upgrade together, such as the Rails gems |

## Rules

### WF-01 — The template build stays in the template (MUST · ADR-01)

The template repository is built by an AI lead and an AI implementer
under `docs/development/protocol.md`. An adopted copy does not inherit
that process. At adoption, step 6 of `00_README.md`:

| Item | Template build only | The adopter |
| --- | --- | --- |
| `docs/development/` | yes | Deletes it, or writes its own process |
| `script/loop/` and its systemd units | yes | Deletes them |
| Lead guard and OpenCode policy checks | yes | Follows its AI files |
| ADR-10 to ADR-14 | yes | Marks them superseded by its own records |
| AI instruction and agent files | yes | Adapts them (`15_working_with_ai.md`) |
| `bin/ci`, `config/ci.rb`, the `ci` workflow | no | Keeps them (WF-02) |
| `script/ci/ruleset_check` | no | Points it at its own repository (WF-03) |
| `VERSION`, release and check workflows | no | Keeps them (WF-03, WF-04) |
| `.github/dependabot.yml` | no | Keeps it (WF-06) |

- The check and release workflows call reusable workflows from
  `yutna/oss-kit` at `@main`. An adopter pins them to a commit SHA or
  copies them in, so a change upstream cannot alter its gate unseen.
- Removing a guard of the template build removes its row from
  `12_enforcement.md` and its step from `bin/ci` in the same pull
  request.

### WF-02 — bin/ci is the one gate (MUST · ADR-19)

- `config/ci.rb` lists every step that decides a merge. `bin/ci` runs
  them in order on a developer machine and in the Dev Container (OPS-01).
- `.github/workflows/ci.yml` runs the same steps as parallel jobs. A step
  added to, removed from or changed in one is changed in the other in
  the same pull request.
- The `ci-ok` job passes only when every other CI job passed. It is the
  one CI check the `main` ruleset requires (WF-03), so a new job counts
  only when `ci-ok` depends on it.
- A step never skips itself on failure: no `|| true`, no
  `continue-on-error`, no condition that hides a red step. A step that
  is not ready is left out, not made optional.
- A failing step is fixed in its pull request or reverted. It is never
  merged red with a promise to fix it later.

### WF-03 — main takes only squash merges of checked pull requests (MUST · ADR-19)

A GitHub ruleset named `main` targets the default branch with:

| Rule | Setting |
| --- | --- |
| Pull request | Required; squash is the only merge method |
| Required status checks | `ci-ok` and `pr-check / check` |
| Non-fast-forward | Blocks force pushes |
| Deletion | Blocks deleting `main` |

- `pr-check` requires a Conventional Commits title
  (`type(scope)!: summary`), gives the pull request exactly one kind
  label (`enhancement`, `bug`, `documentation`, `chore`) from the type,
  adds `breaking` for a `!`, and puts it in an open version milestone.
- The squash commit takes the pull request's title, so `git log` on
  `main` reads as the release notes do.
- One issue becomes one pull request. A pull request closes its issue
  with `Closes #N` in its body.
- `script/ci/ruleset_check` reads the live ruleset in CI and fails when
  any row above is missing; its `--canary` mode proves it fails on a
  broken fixture (TS-07).

### WF-04 — Releases come from VERSION and a closed milestone (MUST · ADR-01)

- `VERSION` holds the last release as `X.Y.Z`, with no `v`. It is
  raised to the milestone's version in a pull request of its own, just
  before the milestone `vX.Y.Z` closes.
- Closing the version milestone `vX.Y.Z` runs `release.yml`. Its
  preflight checks that `VERSION` equals `X.Y.Z` on the commit about to
  be released; when it does not, the milestone is reopened and nothing
  is tagged.
- The release creates the tag `vX.Y.Z` and its notes from the merged
  pull requests, grouped by label through `.github/release.yml`:
  breaking changes, security, features, fixes, documentation,
  dependencies, maintenance.
- Versions follow Semantic Versioning. Before 1.0.0 a breaking change
  raises the minor number.
- Because adopters port releases by hand (ADR-01), the notes of a
  release say for each breaking change what it changes and which ADR or
  rule to read. A pull request labelled `breaking` explains that in its
  body, and the notes link to it.
- A version milestone holds only the work of that release. Work found
  during a milestone goes to the next one.

### WF-05 — Dependencies are pinned exactly and grouped by purpose (MUST · ADR-16)

- Every gem in the `Gemfile` has one exact version (`gem "puma",
  "X.Y.Z"`), with no `~>`, `>=` or missing version. Every package in
  `package.json` has an exact version with no range; `.npmrc` sets
  `save-exact=true` so `npm install` writes one.
- Runtimes come from `mise.toml`; every other pin of them matches it
  (`00_README.md`, Runtimes).
- `Gemfile.lock` and `package-lock.json` are committed. CI installs with
  a frozen Bundler (deployment mode) and `npm ci`, so a lockfile
  that does not match its manifest fails the build.
- The `Gemfile` is grouped by purpose, each group under a comment that
  says what it is for, in this order: framework and server, data,
  security and authorization, API contract, jobs and integrations,
  observability, deployment, then the `development` and `test` groups.
  A gem goes in the group of its purpose; `10_testing.md` lists the
  test gems and their reasons (TS-02).
- A new dependency arrives in the issue that first needs it. Its pull
  request says why it is needed and why the standard library or Rails
  does not cover it. A dependency nothing uses is removed.

### WF-06 — Dependencies are upgraded one pull request at a time (MUST · ADR-16)

- `.github/dependabot.yml` covers every ecosystem the repository has a
  manifest for: `bundler`, `npm`, `github-actions`, `docker` for the
  `Dockerfile`, and `docker-compose` and `devcontainers` for the Dev
  Container (OPS-01).
- Minor and patch updates of one ecosystem come grouped in one pull
  request a week (`groups` with `update-types: [minor, patch]`). A
  major update always comes alone.
- A grouped minor or patch update merges when `bin/ci` is green and no
  changelog in it announces a breaking change.
- A major update, or one that turns CI red, is not merged as it stands.
  It becomes an issue that upgrades the package or its peer group,
  adapts the code and records any changed behaviour in an ADR; the bot's
  pull request is closed with a link to that issue.
- A security advisory from `bundler-audit` (SEC-08) is fixed by
  upgrading, even across a major version, before other work merges; an
  ignore entry instead follows SEC-08.

## Changing a dependency

1. Add or upgrade it with an exact version (WF-05), in its group.
2. Run `bundle install` or `npm install`, and commit the manifest and
   the lockfile together.
3. For a major upgrade, read the changelog, adapt the code, and add an
   ADR when the behaviour changes (WF-06).
4. Run `bin/ci`.
