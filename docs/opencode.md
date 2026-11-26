# OpenCode setup

This repository ships a project-local OpenCode V2 setup for AI-assisted
development. The setup is optional: the Rails application does not depend on
OpenCode, and the repository still works without it.

## What is installed

- `.opencode/skills/` — a vendored copy of the
  [object-oriented design skills](https://github.com/yutna/object-oriented-design-skills)
- `.opencode/opencode.jsonc` — a minimal project configuration
- [AGENTS.md](../AGENTS.md) — the project instructions OpenCode loads

The skills are copied from upstream rather than installed globally so a
repository generated from this template is self-contained.

## Using the skills

OpenCode discovers `.opencode/skills` automatically. The `oo-design` skill is
the index: it sizes a task and names the skill that fits. Ask the agent to load
it before designing a class, module or system.

- `oo-ruby` for plain Ruby with no framework
- `oo-ruby-rails` for Rails code, loaded together with `oo-ruby`: Active
  Record models, controllers, jobs and mailers
- `oo-working-within-a-framework` when the question is how to work with what
  the framework builds or wires

The language skills say the same thing in their "When not to use" sections,
and this pack does not override the framework's conventions.

## Claude Code differences

The pack is written for Claude Code. The skills are copied unchanged because
OpenCode reads the same `SKILL.md` format. The project block lives in
[AGENTS.md](../AGENTS.md) instead of `CLAUDE.md`, and there is no plugin
marketplace or `/plugin install` step. Ignore the pack's Claude Code
installation instructions; the skills are already available under
`.opencode/skills`.

## Source and version

- Upstream: <https://github.com/yutna/object-oriented-design-skills>
- Version: `v1.0.1`
- Commit: `d78a95f03cb8bfefadb13ef487d23bc74d7a9fc5`
- License: MIT; see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)
- Vendored packs: core, Ruby and Ruby on Rails
- Skill count: 48 (46 core + `oo-ruby` + `oo-ruby-rails`)

Version 1 may still add skills in later 1.x releases, and its README warns
that the pack is not universal advice. Treat its rules as advice: this
project's written conventions win.

## Updating the snapshot

When a new upstream release is ready, replace the vendored directories with the
same packs and update the version and commit above.

```sh
git clone --depth 1 --branch v1.0.1 \
  https://github.com/yutna/object-oriented-design-skills.git tmp/oo

rm -rf .opencode/skills/oo-*
cp -R tmp/oo/plugins/core/skills/. .opencode/skills/
cp -R tmp/oo/plugins/ruby/skills/oo-ruby .opencode/skills/
cp -R tmp/oo/plugins/ruby-rails/skills/oo-ruby-rails .opencode/skills/
rm -rf tmp/oo
```

Change the tag in the clone command to the release you are adopting. Review
the diff before committing: upstream may add, remove or rename skills.

Then update:

- the version and commit in this file
- the version and commit in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)

## Validation

From the repository root:

```sh
find .opencode/skills -name SKILL.md | wc -l
opencode debug config
bin/ci
```

The skill count should be 48 for this snapshot. To confirm that OpenCode sees
them, start OpenCode in this repository and type `@oo-design`; the mention
picker should list it together with the other `oo-*` skills. You can also ask
the agent to load `oo-design` directly.

If a skill does not appear:

1. Check that the file is `.opencode/skills/<id>/SKILL.md`.
2. Check that the directory name and the frontmatter `name` match.
3. Check that the frontmatter has a `description`; a skill without one is not
   advertised to the model.
4. Run `opencode debug config` to confirm the project config is loaded.
