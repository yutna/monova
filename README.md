# Monova

[![ci](https://github.com/yutna/monova/actions/workflows/ci.yml/badge.svg)](https://github.com/yutna/monova/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/yutna/monova?sort=semver)](https://github.com/yutna/monova/releases/latest)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Opinionated Ruby on Rails API template built to be the single source of truth
for your modern stack.

Monova is a Rails 8.1 API-only application baseline. The API architecture is
intentionally undecided: this release is the tested Rails baseline plus the
same GitHub workflow used by the rest of
[yutna](https://github.com/yutna)'s public repositories. Do not add layers,
patterns or abstractions until an issue explicitly asks for architecture work.

## Use this template

This repository is a GitHub template. Create a new repository from it:

```sh
gh repo create my-app --template yutna/monova --public
```

Then clone your new repository and follow [Getting started](#getting-started).
The application name, credentials, deployment settings and community files are
all meant to be replaced.

## What is included

- Rails 8.1 in API-only mode
- SQLite for development and test, with separate SQLite databases for
  Solid Cache, Solid Queue and Solid Cable in production
- Active Job, Action Cable and Active Storage (with libvips variants)
- Kamal 2, Thruster and a production Dockerfile
- Minitest, Brakeman, bundler-audit, and RuboCop with rails-omakase
- GitHub Actions CI with a single required `ci-ok` gate, plus the shared
  `pr-check`, `issue-check` and `release` callers from
  [yutna/oss-kit](https://github.com/yutna/oss-kit)
- Community files and issue/pull request templates

## Requirements

- Ruby 4.0.9
- SQLite 3.8 or newer
- libvips (for Active Storage variants)
- Docker (optional, for container builds)

## Getting started

Install dependencies and prepare the database:

```sh
bin/setup --skip-server
```

Start the server:

```sh
bin/dev
```

Open <http://localhost:3000/up>. The template has no application-specific
routes yet; `/up` is the health check used by load balancers and uptime
monitors.

## Credentials

The template intentionally does not ship `config/credentials.yml.enc`. Every
clone creates its own key and encrypted file:

```sh
bin/rails credentials:edit
```

This creates `config/master.key` (ignored by git) and
`config/credentials.yml.enc`. Never commit `config/master.key`. For
production, provide the key as `RAILS_MASTER_KEY`.

## Testing

```sh
bin/rails test
bin/ci
```

`bin/ci` runs setup, RuboCop, the security scans, the test suite and the seed
check. The API baseline has no browser tests; add system tests only when a
change introduces browser behaviour.

## AI-assisted development

The repository includes a project-local OpenCode V2 setup and a vendored copy
of the [object-oriented design skills](https://github.com/yutna/object-oriented-design-skills).
The agent instructions live in [AGENTS.md](AGENTS.md); usage, provenance and
update steps are in [docs/opencode.md](docs/opencode.md). The setup is optional:
the Rails application does not depend on OpenCode.

## Deployment

The production image uses the included Dockerfile, Thruster and a persistent
SQLite volume. Kamal configuration lives in `config/deploy.yml`. Set
`RAILS_MASTER_KEY` in the deployment environment before starting the
application.

## Project structure

```text
app/controllers     request handling; add the API namespace here
app/models          persistence and domain models
app/jobs            background jobs
app/mailers         mailers
config/             environments, routes, deployment and Solid* settings
db/                 schema, seeds and Solid* database schemas
test/               Minitest integration and model tests
docs/               OpenCode and project notes
.opencode/          OpenCode config and vendored design skills
AGENTS.md           project instructions loaded by OpenCode
```

## Documentation

- [OpenCode setup](docs/opencode.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Support](SUPPORT.md)

## Versioning and releases

`VERSION` tracks the template release. The repository uses SemVer and
`vX.Y.Z` milestones; closing a complete milestone creates the tag and GitHub
Release, and GitHub Releases are the changelog. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the day-to-day flow.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md)
first.

## License

[MIT](LICENSE)
