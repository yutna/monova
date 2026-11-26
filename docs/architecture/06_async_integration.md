# 06 — Async and integration

Work that can wait runs as a Solid Queue job, which carries its tenant
(ADR-07), runs at least once and is safe to run again (ADR-23). Calls to
the outside world go through one HTTP client in core, never inside a
database transaction, and webhooks in both directions follow the
Standard Webhooks specification (ADR-24).

## Terms

| Term | Meaning |
| --- | --- |
| Base job | `Acme::Core::Job`, which every job inherits (AUTH-11) |
| Step job | A job that opens the tenancy helper per step, not per `perform` |
| System job | A job that works for every tenant, one tenant at a time |
| Client | An engine's adapter for one outside service, in `app/clients/` |
| Outbound webhook | An event the application sends to a tenant's URL |
| Inbound webhook | A request an outside service sends to the application |
| Endpoint | A tenant's registered webhook URL and its signing secret |

## Rules

### INT-01 — Every job inherits core's base job (MUST · ADR-07)

- Every job inherits `Acme::Core::Job`, defined in core's public
  surface (ARCH-03), and lives in its engine's `app/jobs/` (DOM-01).
- The base job takes `tenant_id:`, `principal_type:` and
  `principal_id:` keyword arguments, sets `Current` from them, and opens
  the tenancy helper (AUTH-09, AUTH-11). A command that enqueues a job
  passes the tenant and the principal it received (AUTH-10).
- A job enqueued in a transaction is pushed only after the commit
  (DOM-05).
- The queue adapter is Solid Queue, in its own `queue` database
  (ADR-04). Engines name no other adapter.

### INT-02 — Job arguments are IDs and plain values (MUST · ADR-23)

- Arguments are record IDs, strings, numbers, booleans and ISO 8601
  times. A record is passed by its ID and loaded in `perform`, inside
  the tenancy helper, so row-level security applies to the load.
- Arguments never carry `personal`, `sensitive` or `secret` values
  (DATA-01, DATA-11): they are stored in the queue database and appear
  in failed executions and logs.
- A job whose record no longer exists finishes without error and logs
  that it found nothing; a missing record is not a retry.

### INT-03 — Every job is safe to run twice (MUST · ADR-23)

Solid Queue delivers at least once: a retry, a manual retry of a failed
execution, or a worker killed after the work but before the job was
marked finished runs `perform` again.

- A job first checks the state it is about to change and returns when
  the work is already done, such as an invoice already sent.
- A job that creates records relies on a unique index (DATA-07), the
  same way `core_event_deliveries` does (DOM-11), so a second run hits
  the index instead of creating a duplicate.
- An effect outside the database carries an idempotency key that stays
  the same on every run: the receiver's own idempotency header when it
  has one, the `webhook-id` for an outbound webhook (INT-10), or the
  ID of the record that caused the effect.

### INT-04 — Retries are declared per error (MUST · ADR-23)

Solid Queue never retries on its own; a job that raises without a
matching `retry_on` becomes a failed execution at once.

- A job lists the transient errors it retries with `retry_on`: the
  client's timeout and connection errors (INT-08), a `5xx` response,
  `ActiveRecord::Deadlocked`. The default is
  `wait: :polynomially_longer, attempts: 5`; a job states another
  schedule only for a reason, as webhook delivery does (INT-11).
- A domain error (DOM-06), `ActiveRecord::RecordInvalid` and
  `ActiveJob::DeserializationError` are never retried; the base job
  discards them, logs the error code, and reports them to error
  tracking (OPS-04).
- `retry_on StandardError` and `rescue StandardError` in a job are not
  used; an unexpected error must reach a failed execution.
- Failed executions are reviewed from the jobs dashboard. Retrying one
  by hand is safe because the job is idempotent (INT-03).

### INT-05 — Concurrency limits are keyed by tenant (SHOULD · ADR-23)

- A job that must not run twice at once for the same thing declares
  Solid Queue's `limits_concurrency` with a `key` that starts with the
  tenant ID, so one tenant's jobs never block another's.
- `limits_concurrency` limits overlap; it is not deduplication. A job
  that must happen once relies on INT-03, not on a concurrency key.
- `on_conflict: :discard` is used only for work that a later run
  repeats in full, such as a recount. `duration` is set to more than
  the job's longest run; Solid Queue's default is 3 minutes.

### INT-06 — No network call inside a transaction (MUST · ADR-23)

A job's tenancy transaction holds a database connection and row locks
for as long as `perform` runs, and a rollback after a successful call
would lose the record of that call.

- A job that calls out, or that runs longer than a few seconds, is a
  step job: it declares `transaction_per_step`. Its `perform` runs with
  `Current` set and no transaction, and each database step runs in
  `with_tenant { ... }`, which opens the tenancy helper for the job's
  tenant (AUTH-09, AUTH-11).
- A step job records the outcome of a call in its own step, after the
  call returns. No client call (INT-08) runs inside `with_tenant`.
- Long work over many records uses Rails 8.1 job continuations
  (`include ActiveJob::Continuable`), one `step` per batch, with the
  cursor advanced after each committed batch. A continuable job is a
  step job, so an interruption never rolls back the progress it
  recorded.
- Core's client raises when it is called while a transaction is open on
  the primary database; a kernel spec proves it (`10_testing.md`).

### INT-07 — Queues, recurring tasks and system jobs are declared (MUST · ADR-23)

- Queues are listed in `config/queue.yml`: `default`, `events` (outbox
  relay and deliveries, DOM-10), `webhooks` (INT-11) and `low`
  (retention purges and reports). A job names its queue with
  `queue_as`; a new queue is added to the file in the same pull request.
- Recurring tasks are listed in `config/recurring.yml` with `class` and
  `schedule`, never `command`, so every task is a job class that
  Packwerk and the specs see.
- A system job (AUTH-11) runs no tenant-owned query itself. It loops
  over `core_tenants` and enqueues one job per tenant, or runs
  `with_tenant` once per tenant. It logs one line per run with its
  class, the number of tenants it touched and their IDs, never names.
- Finished jobs are kept as DATA-15 says. Failed executions are kept
  until someone retries or discards them.

### INT-08 — Outbound HTTP goes through core's client (MUST · ADR-24)

- Every outbound HTTP request goes through `Acme::Core::HttpClient`,
  built on Ruby's `Net::HTTP`. No other HTTP library is installed.
- An engine wraps each outside service in a client class in
  `app/clients/` (DOM-01). The client builds requests with core's
  client and returns value objects (DOM-03), never raw responses.
- Core's client sets explicit timeouts, because `Net::HTTP` waits 60
  seconds by default: open 5 seconds, read and write 10 seconds. A
  client MAY lower them, and raises them only with a stated reason.
- Core's client sets `max_retries` to `0`; `Net::HTTP` otherwise
  repeats an idempotent request once by itself. Retries belong to the
  job (INT-04).
- TLS certificates are always verified. Plain `http` is used only for
  hosts the environment's configuration allows, in development and test.
- Core's client raises typed errors (`Timeout`, `ConnectionFailed`,
  `ResponseError` with the status), which jobs name in `retry_on`.
- It instruments each request with the method, the host, the path
  without its query, the status and the duration. Bodies, query strings
  and authorization headers are never logged (DATA-13).
- A request path makes no outbound call; the work runs in a job and the
  endpoint answers `202` (API-12). An exception needs an ADR that names
  the service and its time budget.

### INT-09 — Tenant-supplied URLs cannot reach private networks (MUST · ADR-24)

A webhook endpoint URL comes from a tenant, so a careless check turns
the delivery job into a request forgery tool against the application's
own network.

- The URL must use `https`, carry no user information, and be at most
  2,048 characters.
- Before each request, core resolves the host and refuses the request
  when any resolved address is loopback, private (RFC 1918, `fc00::/7`),
  shared (`100.64.0.0/10`), link-local (`169.254.0.0/16`, `fe80::/10`,
  which includes cloud metadata addresses), unspecified, multicast, or
  an IPv4-mapped IPv6 form of one of these.
- Core connects to the address it checked, through `Net::HTTP#ipaddr=`,
  while the `Host` header and TLS name stay the URL's host, so a DNS
  answer that changes between the check and the connection is not used.
- The check runs when the endpoint is saved and again at every
  delivery. Redirects are never followed (INT-11).
- A kernel spec proves that each address class above is refused
  (`10_testing.md`).

### INT-10 — Outbound webhooks are signed Standard Webhooks (MUST · ADR-24)

- Core owns `core_webhook_endpoints` (tenant-owned, DATA-03): the URL,
  the event names it subscribes to, the status (`enabled`, `disabled`),
  the signing secret, and during a rotation the previous secret and
  when it expires. Tenant administrators manage endpoints through the
  API with their own scopes (AUTH-05).
- The secret is `whsec_` followed by base64 of 32 random bytes, stored
  with `encrypts` (DATA-12), and shown once when it is created.
- An event is sent as a webhook only when its engine lists it in the
  `webhooks` section of its OpenAPI fragment (API-03), with its payload
  schema. Changing a webhook payload follows the event version rules
  (DOM-09).
- The body is JSON with `id` (the event ID), `type` (the event name),
  `occurred_at` and `data`. `data` carries IDs and `internal` values
  only (DOM-09); the receiver reads the details through the API with
  its own token.
- Each request carries `webhook-id` (the event ID, the same on every
  attempt), `webhook-timestamp` (Unix seconds) and `webhook-signature`:
  `v1,` and the base64 HMAC-SHA256 of `<id>.<timestamp>.<body>`, keyed
  with the decoded secret.
- A rotation keeps the previous secret for 24 hours, and requests in
  that time carry both signatures, separated by a space.

### INT-11 — Webhook deliveries retry on a schedule and are logged (MUST · ADR-24)

- Core subscribes to every event an engine lists as a webhook (DOM-11).
  For each enabled endpoint that subscribes to it, core inserts a row in
  `core_webhook_deliveries`, unique per event and endpoint, and enqueues
  a delivery job on the `webhooks` queue.
- The delivery job is a step job (INT-06). It posts through core's
  client with a total time limit of 15 seconds, which the Standard
  Webhooks specification recommends as the lower bound.
- Only a `2xx` response is a success. A `3xx` is a failure and is not
  followed. A `410` disables the endpoint at once. A `429`, `502`,
  `503` or `504` with `Retry-After` waits that long, up to the next
  step of the schedule.
- Failed attempts retry after 5 seconds, 5 minutes, 30 minutes, then
  2, 5, 10, 14, 20 and 24 hours: the example schedule of the
  specification, adopted here, about three days in total.
- The delivery row records the attempt count, the last status code, the
  last error class, the duration and the next attempt time. It never
  stores the request or response body.
- An endpoint whose deliveries have all failed for five days is
  disabled. Disabling an endpoint, by `410` or by this rule, is audited
  (DATA-14), and the endpoint's status says why.
- Delivery rows are kept 30 days.

### INT-12 — Inbound webhooks are verified and stored once (MUST · ADR-24)

- An outside service posts to `/v1/webhooks/<provider>/<client_id>`.
  Each provider is a controller in the engine that uses it, inheriting
  core's `Acme::Core::WebhooksController`, which checks a signature
  instead of a bearer token (AUTH-04).
- Each receiver is an operation in the engine's fragment (API-03) with
  an empty `security` list. Its request schema is the provider's and
  stays open to added fields, the one exception to closed request
  schemas, because the provider adds fields without notice. The
  signature is checked before the request is validated (API-04).
- The client ID names a machine client of the tenant (AUTH-13) with no
  scopes. Core finds it with the AUTH-07 lookup function, so the tenant
  comes from that record, never from the payload, and an unknown client
  ID gets `404`.
- Inside the tenancy helper for that tenant, core reads the provider's
  secret from `core_inbound_webhook_endpoints` (tenant-owned, secret
  stored with `encrypts`) and verifies the signature over the raw body
  with a constant-time comparison. When the provider sends a timestamp,
  it must be within 5 minutes of the server clock. A failed check gets
  `401` with no detail.
- A verified request is stored in `core_inbound_webhooks`, unique per
  tenant, provider and the provider's event ID, and a processing job is
  enqueued. The response is `200` at once, also for a duplicate, for
  which nothing is stored or enqueued.
- The processing job is idempotent (INT-03) and calls one command of the
  engine (DOM-04). The stored payload is encrypted and kept 7 days.
- A provider that follows Standard Webhooks is verified with the same
  code as INT-10, in reverse.

### INT-13 — Tests never reach the network (MUST · ADR-24)

- The spec helper calls `WebMock.disable_net_connect!`, so any real
  HTTP request in a spec fails.
- Each client in `app/clients/` ships stubs of the outside service's
  responses in its engine's `spec/support/`, taken from the service's
  documentation, and its specs cover a success, a timeout and an error
  response.
- Job specs run jobs with the test adapter and prove a second run
  changes nothing (INT-03). The levels are in `10_testing.md`.

## A new integration

1. Add the client in `app/clients/` on core's client (INT-08), and its
   stubs (INT-13).
2. Call it only from a step job (INT-06) with its retries (INT-04) and
   its idempotency key (INT-03).
3. For an event that tenants receive, list it in the fragment's
   `webhooks` section (INT-10).
4. For a service that calls back, add its webhooks controller and its
   endpoint record (INT-12).
