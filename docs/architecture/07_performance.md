# 07 — Performance

A request does a bounded amount of work: a time budget, a query budget
that does not grow with the page size, and no lazy loading on the way to
the serializer. Tests measure these budgets, so a regression fails the
build instead of a dashboard. Caches are scoped to the tenant, because
neither Solid Cache nor an HTTP cache knows about row-level security
(ADR-25).

## Terms

| Term | Meaning |
| --- | --- |
| Request budget | The time a request may take before the work moves to a job |
| Query budget | The most SQL statements one operation may run |
| N+1 | One query per row of a collection, where one query for all would do |
| Preload | Loading associations up front with `includes` or `preload` |
| Cache key | The full key of a Solid Cache entry, built by core |

## Rules

### PERF-01 — Requests stay within the request budget (MUST · ADR-25)

- The request budget is 1 second at the 95th percentile, measured from
  the moment Puma takes the request to the last byte of the response.
  A read SHOULD answer in 300 milliseconds.
- Work that cannot be shown to fit the budget runs in a job and the
  endpoint answers `202` (API-12). So does every outbound call (INT-08).
- The `acme_app` connections set `statement_timeout` to 5 seconds and
  `idle_in_transaction_session_timeout` to 10 seconds through
  `variables:` in `config/database.yml`, so a runaway query or a
  forgotten transaction ends instead of holding a connection and its
  locks. Migrations use their own timeouts (DATA-05).
- A job step that needs a longer statement runs
  `SET LOCAL statement_timeout` inside its own transaction and states
  the reason in a comment; nothing raises the setting for a whole
  process.
- Response times are logged per operation (OPS-02),
  so the budget is checked against production, not guessed.

### PERF-02 — Collections are bounded and indexed (MUST · ADR-25)

- Every collection is paginated by core's helper with the limits of
  API-06. No endpoint returns an unbounded list, and no association in
  a response is an unbounded list either: a nested collection is its
  own paginated endpoint.
- Every filter and sort field of API-07 is backed by an index that
  starts with `tenant_id` (DATA-03), followed by the filter or sort
  columns and the `id` tie-breaker, so a page is an index range scan.
- The issue that adds a filter or a sort adds its index in the same
  pull request. Its request spec runs the query's `EXPLAIN` with
  `enable_seqscan` turned off for the transaction, because test tables
  are too small for the planner to choose an index, and fails when the
  plan still shows a sequential scan on a tenant-owned table.
- A count of a whole collection is never computed per request (API-06);
  an endpoint that needs one documents a count operation, which MAY use
  a counter column kept by a command.

### PERF-03 — Serializers read only what was preloaded (MUST · ADR-25)

- A serializer is a plain Ruby class in `app/serializers/` (DOM-01) that
  inherits core's `Acme::Core::Serializer`, takes a record, and returns
  a hash in the shape of API-02. No serialization gem is installed, and
  `as_json` or `to_json` of a model is never rendered.
- A serializer reads attributes and associations only. It never calls a
  query, a scope, a command or a policy; anything it needs is preloaded
  by the query object (DOM-07) or computed before rendering.
- Each serializer declares the associations it reads as a frozen
  `PRELOAD` constant in `includes` form. The query object or controller
  applies it, so the serializer and its preload change together.
- Core's pagination helper applies `strict_loading` to the page relation,
  and core's render helper calls `strict_loading!` on a single record
  after authorization and before serialization. A serializer that
  reaches an association that was not preloaded therefore raises
  `ActiveRecord::StrictLoadingViolationError`. Policies run before this
  point, so an association a policy reads stays lazy-loadable.
- `action_on_strict_loading_violation` is `:raise` in development and
  test. In production it is `:log`, and core subscribes to
  `strict_loading_violation.active_record` and reports each one as an
  error with the model and the association (OPS-04),
  so a missed preload slows a response but never breaks it.
- Strict loading marks only the records the relation returns, not the
  records preloaded beneath them; PERF-04 catches the deeper levels.

### PERF-04 — Specs fail on N+1 queries (MUST · ADR-25)

- Prosopite runs around every request spec and job spec with
  `Prosopite.raise = true`, started in a `before` hook and finished in an
  `after` hook, so each example is its own scan. It detects a query
  repeated from the same call stack, at any depth.
- Factory calls are excluded with `Prosopite.pause_during` on factory
  events, so building test data is not reported as an N+1.
- A spec MAY opt out with `prosopite: false` only for a repetition the
  code needs, such as a batch job that processes rows one by one; the
  spec states the reason in its description. `allow_stack_paths` and
  `ignore_queries` stay empty in the template; an entry needs a reason
  in the pull request.
- With PostgreSQL, Prosopite works without `pg_query`; the template does
  not install it, so no native extension is needed.
- Prosopite is not loaded in production. In development it MAY run as
  its Rack middleware with logging only.

### PERF-05 — Every operation has a query budget (MUST · ADR-25)

- The root `config/budgets.yml` holds a `queries:` section beside
  `growth:` (ARCH-10), with one entry per OpenAPI `operationId` and the
  most SQL statements that operation may run.
- The budget counts every statement except schema and transaction
  control (`SCHEMA` and `TRANSACTION` notifications) and query cache
  hits, so it includes the token lookup (AUTH-07) and the tenant's
  `set_config` (AUTH-09).
- Core provides an RSpec matcher that counts `sql.active_record`
  notifications with these exclusions. Each operation's request spec
  runs it against the budget.
- A collection's request spec runs the request with one record and with
  three, and the two counts must be equal: the budget never grows with
  the page.
- A new operation adds its entry in the pull request that adds it; a
  missing entry fails the spec. Raising an entry needs a reason in the
  pull request; lowering one needs nothing.
- Commands are measured by their own specs when they run in a loop,
  such as a step job (INT-06): the count per item stays constant.

### PERF-06 — Authenticated responses are never publicly cacheable (MUST · ADR-25)

Thruster caches any `GET` or `HEAD` response marked `public` with a
`max-age` or `s-maxage`, even when the request carried a bearer token. A
`public` response with tenant data would be served to the next caller.

- Every response to an authenticated request carries
  `Cache-Control: private` and never `public`. Rails' default,
  `max-age=0, private, must-revalidate`, is kept; a resource with an
  `ETag` (API-11) is revalidated with `If-None-Match`.
- Responses that carry a token or a `secret` value, including the token
  endpoint (AUTH-02), carry `Cache-Control: no-store`, as OAuth 2.0
  (RFC 6749) requires for token responses.
- `expires_in` and `http_cache_forever` with `public: true` are used
  only on unauthenticated endpoints that return the same body to
  everyone. A request spec for each authenticated endpoint checks the
  header.
- Thruster compresses responses and pads them against BREACH by
  default; the template keeps that setting
  (OPS-06).

### PERF-07 — Caching goes through core, keyed by tenant (MUST · ADR-25)

The Solid Cache database has no row-level security (DATA-01), so the
key alone keeps one tenant's entries from another's.

- Engines never call `Rails.cache` directly. They call core's
  `Acme::Core::Cache.fetch`, which prefixes every key with the tenant ID
  from `Current` and raises when no tenant is set (AUTH-10).
- When the cached value depends on who asks, the key also carries the
  principal's ID or the scopes that decide what it may see (AUTH-05,
  AUTH-06). A value computed through a policy scope always does.
- Keys are built from IDs and `cache_key_with_version`, never from a
  `personal` or higher value (DATA-11). Values are plain hashes, arrays
  and value objects, never Active Record models.
- A cached value never contains `personal`, `sensitive` or `secret`
  data, so erasing a person (DATA-15) never has to find a cache entry.
- A value is cached only when a spec or a measurement shows that the
  uncached path misses PERF-01 or PERF-05; the pull request says which.
  Each cached call sets `expires_in`, and a hot key sets
  `race_condition_ttl` so concurrent misses do not all recompute it.
- Solid Cache's `max_age` in `config/cache.yml` is 1 day (DATA-15),
  and `max_size` bounds the database. Solid Cache expires entries in
  batches only when the cache is written, so an entry may outlive
  `max_age` while the cache is idle; this is one more reason a value
  holds no `personal` data.

### PERF-08 — Request bodies have a size limit (MUST · ADR-25)

- Thruster refuses bodies over 1 MB with `MAX_REQUEST_BODY`, which is
  unlimited by default. Puma sets `http_content_length_limit` to the
  same value for requests that do not pass through Thruster.
- Both answer `413` themselves, before Rails runs, so that response is
  not a problem document (API-08). The OpenAPI document lists the limit
  and the `413` response for every operation with a body.
- The limit is never raised for one route. A file or a large import
  goes through Active Storage direct uploads (`00_README.md`), and the
  operation takes the upload's signed ID and processes it in a job
  (API-12).

## Checking a new endpoint

1. Write the operation in the contract and its `queries:` budget
   (PERF-05).
2. Add the indexes its filters and sorts need (PERF-02).
3. Declare the serializer's `PRELOAD` and apply it in the query object
   (PERF-03).
4. Run its request spec: Prosopite, strict loading, the query budget and
   the `Cache-Control` check all run there (PERF-04 to PERF-06).
5. Cache only after a measurement says so, through core (PERF-07).
