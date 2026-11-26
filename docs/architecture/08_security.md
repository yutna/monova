# 08 — Security

Most security rules live where the risk lives: tokens and tenancy in
`03_identity_access.md`, personal data in `04_data.md`, outbound calls
in `06_async_integration.md`. This file maps the OWASP API Security
Top 10 (2023) to those rules and adds what has no other home: writable
fields, rate limits, transport, the route inventory, secrets, static
analysis and uploads (ADR-26).

## Terms

| Term | Meaning |
| --- | --- |
| Rate limit | The most requests one key may make in one fixed window |
| Limit key | What a rate limit counts by: a client, a tenant, or a digest |
| Digest | HMAC-SHA256 of a normalized value with a credentials key (DATA-12) |
| Credentials | The encrypted Rails credentials file of one environment |
| Route inventory | Every route the application answers |

## OWASP API Security Top 10 (2023)

| Risk | Answered by |
| --- | --- |
| API1 Broken Object Level Authorization | AUTH-08, AUTH-09, AUTH-12 |
| API2 Broken Authentication | AUTH-01 to AUTH-04, SEC-03 |
| API3 Broken Object Property Level Authorization | SEC-01, API-03, PERF-03 |
| API4 Unrestricted Resource Consumption | SEC-02, API-06, PERF-01, PERF-08 |
| API5 Broken Function Level Authorization | AUTH-05, AUTH-06 |
| API6 Unrestricted Access to Sensitive Business Flows | SEC-03, API-10 |
| API7 Server Side Request Forgery | INT-08, INT-09 |
| API8 Security Misconfiguration | SEC-04, SEC-05, API-13, PERF-06 |
| API9 Improper Inventory Management | SEC-06, API-03, API-05 |
| API10 Unsafe Consumption of APIs | INT-08, INT-12, SEC-08 |

A new rule that answers one of these risks adds its ID to this table.

## Rules

### SEC-01 — Writable fields are allowed per action (MUST · ADR-26)

The request schema says which fields exist (API-03); the controller
says which of them this caller may set.

- Every action that writes reads its body with `params.expect`, which
  permits the named keys and answers `400` when the root key is missing.
  `permit!`, `to_unsafe_h` and passing `params` straight to a model or a
  command are never used.
- `id`, `tenant_id`, `created_at`, `updated_at`, foreign keys that place
  a record in a tenant or under an owner, and any state column
  (DOM-08) are never permitted. The tenant comes from the token
  (AUTH-07); an ID in the body is loaded through the caller's scope
  (AUTH-08); a state changes only through a named transition.
- A field that only some callers may write, such as a role or a
  discount, is filtered by the policy with Action Policy's
  `params_filter`, so the rule sits beside the action's authorization
  (AUTH-06). A caller who sends a field they may not write gets `403`
  `forbidden`, never a silent drop.
- Responses are built by serializers that list their fields (PERF-03),
  and a `secret` value is never serialized (DATA-11).
- A request spec for each writing action sends a field the caller may
  not set and checks that it is refused (`10_testing.md`).

### SEC-02 — Every request passes a rate limit (MUST · ADR-26)

Core's base controller applies Rails `rate_limit`, which counts in the
cache store with one fixed window per key. Engines never declare their
own limits outside core's helpers, so every key follows PERF-07's
discipline even though the counters are not tenant data.

| Limit | Key | Default |
| --- | --- | --- |
| Every request, before authentication | Client IP digest | 1,000 per minute |
| Every authenticated request | Tenant ID and client app ID | 600 per minute |
| Every authenticated request | Tenant ID | 3,000 per minute |

- The health check (OPS-05) is the only route outside core's base
  controller; it touches no database and has no limit.
- The defaults live in `config/rate_limits.yml`, which core reads at
  boot, so an adopter tunes a number without touching code. An endpoint
  MAY have a tighter limit through core's helper; none has a looser one.
- A limit key never holds a `personal` value (DATA-11). An IP address
  is `personal`, so the key carries its digest, never the address.
- Over a limit, the error responder renders `429` `rate_limited` with
  `Retry-After` set to the window length in seconds (API-14).
- `request.remote_ip` trusts loopback and private ranges by default,
  which covers kamal-proxy and Thruster on the same host. A deploy that
  puts another proxy or a CDN in front adds its ranges to
  `config.action_dispatch.trusted_proxies`; otherwise every caller
  shares the proxy's limit (OPS-06).
- In production the store is Solid Cache, whose `increment` locks the
  entry's row and keeps its first expiry, so concurrent requests count
  correctly. The test environment uses `:null_store`, which never
  counts; core's rate limit specs swap in an
  `ActiveSupport::Cache::MemoryStore` and prove each limit answers
  `429` (`10_testing.md`).

### SEC-03 — Sign-in and sensitive flows have their own limits (MUST · ADR-26)

The token endpoint (AUTH-02) is the one place a guess can pay off, so it
has limits beyond SEC-02.

| Grant | Key | Default |
| --- | --- | --- |
| `user_password` | Digest of the normalized email | 5 per 15 minutes |
| `user_password` | Digest of the client IP | 20 per minute |
| `client_secret` | Client ID | 30 per minute |
| `refresh_token` | Client app ID | 60 per minute |

- The email key uses the same digest as the email lookup (DATA-12), so
  the limit and the lookup agree on what counts as one address.
- A limited sign-in answers `429`, not `401`, and the response is the
  same whether or not the account exists (AUTH-02).
- No lockout disables an account after failed attempts, because it lets
  anyone lock out any user; the limit slows the guessing instead.
- Each failed grant and each `429` on this endpoint is logged with the
  client ID and the limit name, never the email or the password
  (DATA-13), so an attack shows in the logs (OPS-02).
- Any other flow that costs money or reveals whether something exists,
  such as sending an invitation or a verification message, gets its own
  limit through core's helper, keyed by tenant and principal, and its
  issue names the limit.

### SEC-04 — Production serves only TLS, for known hosts (MUST · ADR-26)

- kamal-proxy terminates TLS. Production sets `config.assume_ssl` and
  `config.force_ssl` to `true`, so every response carries
  `Strict-Transport-Security` (two years, with subdomains, the Rails
  default) and a plain HTTP request is redirected, never served. The
  health check path is excluded from the redirect so the proxy can reach
  it over HTTP.
- `config.hosts` lists the production host names, and
  `config.host_authorization` excludes only the health check path, so a
  request with another `Host` header is refused before routing.
- No production setting turns off a Rails protection that is on by
  default. A change to one needs an ADR.
- Production uses its own credentials, databases, storage bucket and
  keys. No environment other than production holds production data.

### SEC-05 — Responses reveal nothing about the internals (MUST · ADR-26)

- `consider_all_requests_local` is `false` in production. An unexpected
  error renders the `internal_error` problem (API-09) with the request
  ID and no message, class name, backtrace or SQL. The detail goes to
  the error report, filtered (DATA-13).
- A validation problem names the field and the rule it broke, never the
  value that was sent.
- Rails' `default_headers` are kept: `X-Content-Type-Options: nosniff`,
  `X-Frame-Options`, `X-Permitted-Cross-Domain-Policies` and
  `Referrer-Policy`. An entry is never removed.
- Every response body is JSON with its declared media type,
  `application/json` or `application/problem+json`, so no client sniffs
  it as anything else.

### SEC-06 — Every reachable route is in the contract (MUST · ADR-26)

- A kernel spec lists `Rails.application.routes` in the production
  environment and fails when a route has no operation in the bundle
  (API-03). The health check (OPS-05) is in the bundle too, with an
  empty `security` list.
- `config.active_storage.draw_routes` is `false`, because Active
  Storage's default routes, including its direct upload endpoint, need
  no authentication. Uploads go through core (SEC-09).
- A version that is no longer served is removed from the routes and the
  bundle together (API-05); nothing stays reachable because it was
  forgotten.
- No debug, admin or diagnostic endpoint is mounted in production. Mission
  Control and similar dashboards run only where `Rails.env.local?` is
  true, or behind their own ADR.

### SEC-07 — Secrets live in credentials or the deploy's secrets (MUST · ADR-26)

- Application secrets (the Active Record encryption keys, the digest
  keys of DATA-12, signing keys) live in the credentials of each
  environment, `config/credentials/<environment>.yml.enc`. The key
  files are ignored by git and by Docker, and the production key
  reaches the container only as `RAILS_MASTER_KEY` from Kamal secrets.
- `.kamal/secrets` SHOULD read from a password manager through
  `kamal secrets fetch`, never from a file in the repository.
- Database role passwords (DATA-02) are set in the environment of the
  run that needs them and are never written to a file in the repository
  or the image.
- Request logs, error reports and traces never contain the
  `Authorization` header or any value that `filter_parameters` names
  (DATA-13), so a bearer token (AUTH-01) or a client secret never leaves
  the request.
- Every secret has a rotation path: encryption keys through `previous`
  (DATA-12), client secrets with an overlap (AUTH-02), webhook secrets
  as INT-10 says. A secret that may have leaked is rotated first and
  investigated after.
- The repository has GitHub secret scanning with push protection turned
  on, so a committed secret is blocked or reported.

### SEC-08 — Code and dependencies are scanned in CI (MUST · ADR-26)

- `bin/ci` runs Brakeman with `--exit-on-warn`, so any warning fails the
  build. A false positive goes into `config/brakeman.ignore` with a note
  that says why it does not apply.
- `bin/ci` runs `bundler-audit` against an advisory database updated in
  the same run. Each entry in the ignore list of
  `config/bundler-audit.yml` carries a comment with the reason and a
  review date; an entry without both is removed.
- The dependency bot opens updates for Bundler, npm and GitHub Actions
  (`00_README.md`); a security update is reviewed before any other
  pull request.
- Both tools are listed as review in `12_enforcement.md` until a canary
  proves that each one fails on a known violation.

### SEC-09 — Uploads are authenticated, bounded and typed (MUST · ADR-26)

Active Storage is available for files (ADR-20); these controls apply
whenever an application uses it.

- Core provides the direct upload endpoint in its OpenAPI fragment,
  behind authentication and a scope (AUTH-05). It checks the declared
  byte size and content type against the attachment's limits before it
  creates the blob.
- Each attachment declares a content type allow-list and a maximum
  size. The model validates both when the signed blob ID is attached,
  and the job that processes the file (API-12) checks the stored
  content type again, because a client can declare any type.
- Production stores files in a private bucket. `urls_expire_in` is set
  to 5 minutes, because Active Storage's redirect URLs never expire by
  default, and every file URL is created after the record is authorized
  (AUTH-08).
- A blob that no record attaches is purged by a recurring job after
  1 day (INT-07, DATA-15).

## Checking a new endpoint

1. Permit only the fields the action allows, and filter the rest through
   the policy (SEC-01).
2. Give a flow that costs money or reveals existence its own limit
   (SEC-03).
3. Add the operation to the contract before the route, so the inventory
   spec stays green (SEC-06).
4. Run `bin/ci`: Brakeman and `bundler-audit` run there (SEC-08).
