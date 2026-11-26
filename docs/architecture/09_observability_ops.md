# 09 — Observability and operations

How the application is developed, observed, deployed and recovered. An
operator who reads a log line, a trace or an error report must be able
to follow one request or one job from end to end, without seeing
personal data (DATA-13) (ADR-27). Deployment and backups follow Kamal
(ADR-18); the development environment is a Dev Container (ADR-17).

## Terms

| Term | Meaning |
| --- | --- |
| Event | A structured record reported through `Rails.event` |
| Request ID | The `X-Request-Id` value `ActionDispatch::RequestId` sets |
| Trace | An OpenTelemetry trace, joined across services by W3C headers |
| Release step | The one-off container that migrates before a deploy boots |
| Pin file | `mise.toml`, the Dev Container files, the lockfiles, `Dockerfile` |
| Runbook | A page that says how to diagnose and fix one kind of incident |

## Rules

### OPS-01 — The Dev Container is proven in CI (MUST · ADR-17)

- `.devcontainer/` holds a Compose file with two services: the
  application, which installs Ruby and Node from `mise.toml`, and
  PostgreSQL, from an image pinned by version and `sha256` digest.
- The same PostgreSQL image reference, version and digest, is used by
  the Dev Container, the CI database service and the Kamal accessory
  (OPS-07). A check in `bin/ci` fails when the three differ.
- A CI job builds the container and runs `bin/ci` inside it whenever a
  pin file changes, and on a weekly schedule, so a pull request that
  breaks the container fails, and so does a base image that rots.
- `bin/setup --skip-server` inside the container creates the roles
  (DATA-02), the databases and the seeds (DATA-16), and needs no other
  manual step.

### OPS-02 — Production logs are one JSON object per line (MUST · ADR-27)

Rails 8.1 reports structured events through `Rails.event`, and the
framework's structured subscribers emit events such as
`action_controller.request_completed` and `active_job.completed`.
Rails adds no subscriber that writes them anywhere, so core adds one.

- Core's log subscriber writes every event to standard output as one
  JSON object: `name`, `payload`, `tags`, `context`, `timestamp` and
  the source location. Kamal collects standard output (`kamal app
  logs`); the application writes no log file in production.
- In production core detaches Rails' text log subscribers for Action
  Controller, Active Record and Active Job, so the structured event is
  the only line a request or a job writes, and `Rails.logger` uses a
  JSON formatter, so every line on standard output parses.
- The production level is `info`, fixed in
  `config/environments/production.rb`; no environment variable raises
  it to `debug`, which logs SQL and its bound values (DATA-13).
- `Rails.event` filters hash payloads with `filter_parameters`, but not
  event objects. Core reports hashes only; an event object needs its
  own filter and a spec.
- Active Job adds a job's arguments to its events while
  `log_arguments?` is true, the default. Core's base job sets it to
  `false` (INT-01), and a spec checks it for every job class.
- `action_controller.request_completed` carries the duration, the
  database time and the query count. Core adds the operation ID
  (API-03), the tenant ID and the client app ID to the context, so
  response times are read per operation against PERF-01.
- A log spec in core sends a request with a filtered parameter and a
  bearer token and fails when either appears in the output.

### OPS-03 — Every request and job carries a request ID and a trace (MUST · ADR-27)

- `ActionDispatch::RequestId` accepts an incoming `X-Request-Id`, keeps
  only letters, digits, `_`, `-` and `@`, cuts it to 255 characters, or
  makes a UUID; it returns the value in the response header. The
  problem body's `request_id` (API-08) is the same value.
- Rails clears the event context before and after each request but
  never fills it. Core's base controller sets `request_id`, `trace_id`,
  `tenant_id` and the client app ID once the token is verified
  (AUTH-10).
- Core's base job stores the enqueuing request ID with the job and sets
  it, the job ID and the tenant ID in the context when it runs, so a
  job's lines join the request that enqueued it.
- Core configures the OpenTelemetry SDK with the Rails, Rack, `pg` and
  `Net::HTTP` instrumentations. Incoming W3C `traceparent` headers are
  honoured, core's HTTP client (INT-08) sends `traceparent` on every
  call, and the Active Job instrumentation links a job's trace to the
  request's (its default `propagation_style: :link`).
- The `pg` instrumentation keeps its default `db_statement: :obfuscate`
  (or `:omit`), never `:include`, so a span never holds a bound value.
  Span attributes follow DATA-13 like log fields.
- The SDK always creates spans, so log lines carry a `trace_id`. Spans
  are exported only when `OTEL_EXPORTER_OTLP_ENDPOINT` is set in the
  deploy's environment; otherwise `OTEL_TRACES_EXPORTER` is `none`. The
  service name is set through `OTEL_SERVICE_NAME`.

### OPS-04 — Errors are reported through Rails.error (MUST · ADR-27)

- Every exception that core's error responder turns into a `500`
  (API-08), and every one rescued but worth an operator's attention,
  goes through `Rails.error` with the request ID and the trace ID in its
  context. Code never calls an error vendor's SDK directly.
- Core subscribes one reporter to `Rails.error` that writes an
  `error.reported` event (OPS-02). An adopter adds a vendor's subscriber
  next to it; the vendor's gem gets its own ADR and is configured to
  send no request body, headers or user data (DATA-13).
- Jobs: Solid Queue reports an execution that fails through
  `Rails.error` (its default `on_thread_error`), and the base job
  reports the errors it discards (INT-04).
- A strict loading violation in production is reported, not raised
  (PERF-03).
- Error reports carry the release (`VERSION` and the image's Git SHA)
  so an error is tied to a deploy.

### OPS-05 — The health check proves the process is up (MUST · ADR-18)

- `GET /up` is Rails' `Rails::HealthController`: `200` when the
  application booted, `500` when it raises. It does not touch the
  database, so a database outage does not take every container out of
  the proxy at once.
- It is the only route outside core's base controller: it has no bearer
  token, no tenant and no rate limit (SEC-02), and it does no work worth
  limiting. The contract lists it with an empty `security` list
  (API-03, AUTH-04).
- It is excluded from the TLS redirect and from host authorization
  (SEC-04), and `silence_healthcheck_path` keeps it out of the logs.
- kamal-proxy checks `/up` during a deploy and routes traffic to a new
  container only after it answers `200`.
- Database reachability is proven by the release step (OPS-07) on each
  deploy and by the database alerts the adopter sets up (OPS-09).

### OPS-06 — Thruster and Puma run with their defaults (SHOULD · ADR-15)

- The image starts `bin/thrust bin/rails server`. Thruster's compression
  and caching defaults are kept (PERF-06); a change states its reason
  in the pull request.
- Solid Queue runs inside Puma (`SOLID_QUEUE_IN_PUMA`) on a single
  server. A deploy with more than one server, or with job load that
  slows requests, moves the jobs to their own Kamal role running
  `bin/jobs`.
- A proxy or CDN in front of kamal-proxy adds its address ranges to
  `config.action_dispatch.trusted_proxies`, or every caller shares the
  proxy's rate limit (SEC-02). A limit per connection belongs to that
  proxy, not to Rails (ADR-26).

### OPS-07 — Kamal deploys, and only the release step migrates (MUST · ADR-18)

- `config/deploy.yml` deploys the image with Kamal and runs PostgreSQL
  as an accessory from the image pinned in OPS-01, with its data on a
  named volume. The servers, the registry and the hosts are
  placeholders the adopter replaces.
- The web and job containers get the `acme_app` credentials only
  (DATA-01). The entrypoint never runs `db:prepare` or `db:migrate`.
- The `pre-deploy` hook, which Kamal runs after the image is pushed and
  before it boots, is the release step: it runs `bin/rails db:migrate`
  for every database in a one-off container of the new image
  (`kamal app exec --version "$KAMAL_VERSION"`), passing the
  `acme_migrator` credentials from `.kamal/secrets` with `--env`. Those
  credentials are never listed under `env.secret`.
- A failed migration stops the deploy before any container changes.
  Migrations are zero-downtime (DATA-05), so the old containers keep
  serving against the new schema while the new ones boot.
- `kamal rollback` returns to the previous image. A migration is never
  rolled back in production; a forward migration fixes it.

### OPS-08 — Backups are taken daily and restored on a schedule (MUST · ADR-18)

- A recurring task (INT-07) on a host other than the database's runs
  `pg_dump --format=custom` of the primary and the queue databases as
  `acme_backup` (DATA-01), encrypts the dump, and writes it to storage
  off the database host. The cache and cable databases are not backed
  up; they rebuild themselves.
- Backups are kept for 30 days. A deleted tenant's rows are erased 30
  days after the deletion (DATA-15), so they leave the last backup at
  most 60 days after it. A restore re-runs the tenant erasure job before
  the application serves traffic.
- Point-in-time recovery with WAL archiving needs a role with
  `REPLICATION`, which DATA-01 does not grant; an adopter who needs a
  smaller recovery point adds it in an ADR.
- A restore into a scratch database is rehearsed at least once a
  quarter, following the restore runbook, and its date and duration are
  recorded there. A backup that has never been restored does not count.

### OPS-09 — Runbooks and alerts exist before the first real user (SHOULD · ADR-18)

- `docs/runbooks/` holds one page per incident kind: deploy and
  rollback, failed migration, restore from backup, rotate a credential
  (SEC-07), revoke every token of a tenant (AUTH-03), drain a stuck
  queue, and a database that is out of disk.
- Each page names the symptom, the commands, how to confirm the fix, and
  who is told.
- Alerts cover at least: the `5xx` rate, the p95 duration per operation
  against its budget (PERF-01), failed job executions, the oldest ready
  job's age, the backup's age, and the database disk.
- An alert links to its runbook page.

## Follow-ups that are not rules

The template ships placeholders for the deploy, the backup storage and
the alert targets. Each adopter fills them in before the first real
user (`00_README.md`, step 7).
