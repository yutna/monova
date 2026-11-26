# 03 — Identity and access

Every request names a caller with a bearer token, belongs to the one
tenant that token carries, and is authorized twice: the token's scopes
limit what the client may do, and a policy decides what the caller may
do to each record (ADR-06). PostgreSQL row-level security keeps each
tenant's rows apart even when application code forgets a scope
(ADR-07). Core implements all of it (ARCH-03); engines use it through
the base controller, the base policy and the base job.

## Terms

| Term | Meaning |
| --- | --- |
| Tenant | The customer account that owns data; one row in `core_tenants` |
| Principal | Who acts: a user, or a machine client |
| User | A person, global in `core_users`, a member of one or more tenants |
| Membership | A user's role in one tenant, in `core_memberships` |
| Machine client | A program of one tenant, in `core_machine_clients` |
| Client app | A first-party app registered in core, identified by a client ID |
| Access token | An opaque bearer string that authenticates one request |
| Refresh token | An opaque string that obtains a new access token, users only |
| Scope | A permission string a token carries |

## Rules

### AUTH-01 — Tokens are opaque and stored only as digests (MUST · ADR-06)

- An access or refresh token is a fixed prefix followed by at least 32
  random bytes from `SecureRandom`, encoded in base58:
  `acme_at_...` for access tokens, `acme_rt_...` for refresh tokens.
  The prefix lets secret scanners and log filters recognise a leaked
  token.
- The database stores an HMAC-SHA256 digest of the token, keyed with a
  secret from the Rails credentials, never the token itself. A slow
  password hash is not needed because the token has full entropy, and a
  keyed digest stays useless to anyone who copies only the database.
- `core_tokens` holds, per token: the digest (unique index), the kind
  (access or refresh), the tenant, the principal, the client app, the
  scopes, `expires_at`, `revoked_at`, `last_used_at` and, for refresh
  tokens, the family it belongs to.
- The token string appears once, in the response that issues it. It is
  never logged, stored, returned again or put in a URL; the parameter
  and header filters cover it (`08_security.md`).
- Self-contained tokens such as JWTs are not used (ADR-06).

### AUTH-02 — One token endpoint issues tokens (MUST · ADR-06)

Core exposes `POST /v1/auth/tokens`, documented in core's OpenAPI
fragment (API-03). Its response borrows the fields of the RFC 6749
§5.1 token response: `access_token`, `token_type` (`Bearer`),
`expires_in`, `scope` and, for users, `refresh_token`. Errors are
problems (API-08). The endpoint is not an OAuth 2.0 authorization
server and does not claim to conform to one.

- `user_password`: a user signs in through a client app with the client ID,
  email, password and tenant, and gets an access and a refresh token.
- `refresh_token`: a user's client app trades a refresh token for a new
  pair (AUTH-03).
- `client_secret`: a machine client proves its client ID and
  secret, and gets an access token only.

- `user_password` is accepted only from client apps registered as
  first-party, which are the only clients (ADR-02). RFC 9700 §2.4 says
  the OAuth resource owner password grant MUST NOT be used, for any
  client. Monova deviates on purpose: it has no third-party clients and
  no OAuth server, and a first-party sign-in form already holds the
  password. An application that lets third parties call its API on a
  user's behalf adds an ADR and OAuth 2.0 authorization code with PKCE
  instead.
- Passwords use `has_secure_password`. Machine client secrets are
  stored as digests like tokens (AUTH-01) and can be rotated with an
  overlap period.
- A user who belongs to several tenants names one at sign-in and gets a
  token for that tenant only. Switching tenant means a new token.
- Every failed grant answers the same `401` `unauthenticated`, whether
  the email, the password, the client or the tenant was wrong, so the
  endpoint does not reveal which accounts exist. Sign-in attempts are
  rate limited per client and per email (`08_security.md`).

### AUTH-03 — Tokens expire, rotate and can be revoked (MUST · ADR-06)

| Token | Lifetime |
| --- | --- |
| Access token | 15 minutes |
| Refresh token | 30 days, and at most 90 days per family |
| Machine client access token | 1 hour |

- Each application MAY change these lifetimes in an ADR; it never makes
  an access token live longer than 24 hours.
- Using a refresh token revokes it and issues a new pair in the same
  family. Presenting a refresh token that was already used revokes the
  whole family, because one of the two holders is an attacker.
- `DELETE /v1/auth/tokens/current` revokes the presented token, and its
  family for a user. Changing a password, removing a membership,
  suspending a tenant and rotating a machine client's secret revoke
  every token they cover.
- Revocation sets `revoked_at` and takes effect on the next request.
  Expired and revoked rows are deleted by a recurring job after 30
  days.
- `last_used_at` is written at most once a minute per token, so a busy
  client does not turn every read into a write.

### AUTH-04 — Every request authenticates in the base controller (MUST · ADR-06)

- Core's base controller reads the token only from the `Authorization:
  Bearer` header (RFC 6750 §2.1), with Rails'
  `authenticate_with_http_token`. A token in a query parameter or a
  body is ignored.
- It digests the token and looks it up (AUTH-07). A missing, unknown,
  expired or revoked token, or a refresh token presented as an access
  token, gets `401` `unauthenticated` with a
  `WWW-Authenticate: Bearer` header (RFC 6750 §3). The problem does not
  say which of these it was.
- Only the token endpoint (AUTH-02) and the health checks
  (`09_observability_ops.md`) skip authentication, and the document
  marks them with an empty `security` list (API-03).
- Authentication happens before any other work, including request
  validation (API-04), so an anonymous caller learns nothing about the
  shape of an endpoint.

### AUTH-05 — Scopes are checked from the contract (MUST · ADR-06)

- A scope is `<engine>:<resource>:<access>`, where access is `read` or
  `write`: `billing:invoices:read`. `write` does not include `read`.
- Each operation lists the scopes it requires in its `security`
  requirement in the OpenAPI document (API-03). The base controller
  takes them from the operation that `openapi_first` matched for the
  request (`validate_request` returns it with the validation result)
  and checks them against the token's scopes before it renders any
  validation failure. A
  controller never lists scopes itself, so the contract and the check
  cannot drift.
- A missing scope gets `403` `forbidden` with
  `WWW-Authenticate: Bearer error="insufficient_scope"` and the required
  scopes (RFC 6750 §3.1).
- A token's scopes are those the client asked for, cut down to what the
  principal may hold: a membership's role grants a set of scopes, and a
  machine client is registered with its own. Roles and their scope sets
  are configuration in core, not rows a tenant edits.
- Scopes say what a client may call. They never decide whether a caller
  may touch a particular record; that is the policy's job (AUTH-06).

### AUTH-06 — Every action is authorized by a policy (MUST · ADR-06)

- Each engine has one Action Policy class per model it exposes, under
  `engines/<engine>/app/policies/`, inheriting core's base policy.
- The base policy declares `authorize :principal` and
  `authorize :tenant` as its authorization context, and keeps Action
  Policy's default rule `manage?` returning `false`, so a rule nobody
  wrote denies.
- Core's base controller supplies that context and runs
  `verify_authorized` after every action. An action that never called
  `authorize!` fails in every environment, not only in tests.
- A member action calls `authorize!` on the record it loaded (AUTH-08).
  A collection action calls `authorize!` for the collection and loads
  its rows through `authorized_scope`, which applies the policy's
  scope for Active Record relations.
- `ActionPolicy::Unauthorized` is rescued once, in core, and rendered as
  `403` `forbidden`, or as `404` `not_found` when the caller may not
  see the record at all (AUTH-08).
- Rules read the principal, the tenant and the record. They do not read
  `params`, the request or `Current` (AUTH-10).
- `pre_check` MAY grant or deny shared cases, such as a suspended
  membership, in the base policy. Engines do not add an "admin may do
  anything" pre-check; each rule says what an administrator may do.

### AUTH-07 — The tenant comes from the token only (MUST · ADR-07)

- The tenant of a request is the tenant of its token. A tenant ID in a
  path, a query, a header or a body never selects the tenant; at most it
  is checked against the token's tenant and refused with `404` when it
  differs.
- At sign-in the tenant the user names is accepted only when the user
  has an active membership in it, checked inside a transaction set to
  that tenant (AUTH-09). The token then carries that tenant.
- Two lookups must run before the tenant is known: a token by digest
  and a machine client by client ID. Each is a PostgreSQL function in
  core marked `SECURITY DEFINER`, with a fixed `search_path`, that takes
  the one key and returns only the columns authentication needs.
- Those functions are owned by a dedicated authentication role that
  cannot log in, has no `BYPASSRLS`, may only `SELECT` from
  `core_tokens` and `core_machine_clients`, and is the only role named
  in an extra row-level security policy on those two tables. It is the
  one exception to AUTH-09; no other code reads a tenant-owned table
  without a tenant. `04_data.md` creates the role with the others.
- `core_tenants` and `core_users` are the only global tables, so a user
  is found by email without a tenant. They hold identity, never tenant
  data; only core maps them (ARCH-07).

### AUTH-08 — Records are found through the caller's scope (MUST · ADR-06)

Broken object level authorization is the first risk in the OWASP API
Security Top 10 (2023). Every endpoint that takes a record ID closes it
in three layers:

1. Row-level security returns no row of another tenant (AUTH-09).
2. The record is loaded through `authorized_scope`, by its public ID
   (`04_data.md`), never with a bare `find` on the model.
3. `authorize!` checks the rule for the action on that record.

- A record of another tenant, or one outside the caller's scope, gets
  `404` `not_found`, the same answer as an ID that does not exist
  (API-09). A record the caller may see but not change gets `403`
  `forbidden`.
- A child resource (API-01) is loaded through its parent, which is
  authorized first.
- An ID in a request body that points to another record, such as a
  customer ID on a new invoice, is loaded and authorized the same way
  before it is used.
- Every endpoint that takes an ID has a request spec in which a caller
  of another tenant and a caller of the same tenant without access both
  get the documented answer (`10_testing.md`).

### AUTH-09 — Each transaction sets its tenant, and RLS holds it (MUST · ADR-07)

- Every tenant-owned table has `tenant_id` and a row-level security
  policy, created in the migration that creates the table, with
  `FORCE ROW LEVEL SECURITY` so the policy also binds the table's
  owner. `04_data.md` defines the column, the roles and the policy
  migration helper.
- The policy compares `tenant_id` with a transaction-local setting, in
  both `USING` and `WITH CHECK`, so a row can be neither read nor
  written for another tenant:

  ```sql
  tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
  ```

  With no tenant set the comparison is `NULL`, so no row matches.
- Core's tenancy helper opens a transaction and runs
  `SELECT set_config('app.tenant_id', $1, true)` as its first
  statement. The third argument makes the setting local to the
  transaction, like `SET LOCAL`, so it ends with the transaction and
  never leaks to the next user of a pooled connection.
- The base controller wraps the whole action, from authorization to
  rendering, in that helper. Nothing else sets `app.tenant_id`.
- The runtime database role owns no table and has neither `BYPASSRLS`
  nor superuser rights, both of which skip every policy (ADR-07). A
  canary spec proves that a query without a tenant returns no rows and
  that an insert for another tenant fails (`10_testing.md`).

### AUTH-10 — Current attributes carry context, not decisions (MUST · ADR-07)

- `Acme::Core::Current`, an `ActiveSupport::CurrentAttributes` class,
  holds the tenant, the principal, the token and the request ID for one
  request or one job. Rails clears it when the executor finishes a
  request or a job that runs through Active Job's `execute`; core's
  base job does not rely on that and sets every attribute itself
  (AUTH-11).
- Only the base controller and the base job assign it. Logging, audit
  records (`04_data.md`) and the tenancy helper read it.
- Commands, queries and policies receive the principal and the tenant
  as arguments (`05_domain.md`). They do not read `Current`, so they
  behave the same in a request, a job and a spec.
- Domain engines never define their own current attributes.

### AUTH-11 — Jobs carry the tenant explicitly (MUST · ADR-07)

- Core's base job takes the tenant ID and the principal as part of its
  arguments when it is enqueued, from the caller's context, and runs
  `perform` inside the tenancy helper (AUTH-09) for that tenant.
- `Current` is not carried into a job; the job sets it again from its
  arguments. A job enqueued without a tenant fails before `perform`.
- A job that works for every tenant is declared as a system job. It
  runs no tenant-owned query itself; it enqueues one job per tenant, or
  opens the tenancy helper for one tenant at a time. Each run is
  logged with the tenants it touched (`06_async_integration.md`).

### AUTH-12 — No runtime path crosses tenants (MUST · ADR-07)

- No request, job or console task reads or writes two tenants in one
  transaction. Work across tenants, such as operator reports, loops over
  tenants with one transaction each (AUTH-11).
- A role with `BYPASSRLS` is used only for migrations and backups
  (`04_data.md`, `09_observability_ops.md`), never by the application.
- An application that needs a true cross-tenant read, such as a support
  console, adds an ADR that names the role, how its use is audited, and
  who may run it.

### AUTH-13 — Machine clients are tenants' integrations (SHOULD · ADR-02)

- A machine client belongs to one tenant, has a name, a secret, its
  scopes, and the membership that created it as its owner. Removing that
  membership does not delete the client; a tenant administrator
  reassigns or revokes it.
- A machine client gets only the scopes its task needs, and never the
  scopes that manage tokens, memberships or other machine clients.
- Policies treat a machine client as its own principal type. A rule
  that should apply to machine clients says so; the base policy denies
  them by default.

## Request path

1. The base controller reads the bearer token and finds it by digest
   (AUTH-04, AUTH-07). Failure: `401`.
2. It opens a transaction with the token's tenant set (AUTH-09) and
   fills `Current` (AUTH-10).
3. It matches the request to its operation in the contract and checks
   the operation's scopes (AUTH-05). Failure: `403`.
4. It renders any validation failure from that match (API-04).
   Failure: `400` or `422`.
5. The action loads records through `authorized_scope` and calls
   `authorize!` (AUTH-06, AUTH-08). Failure: `404` or `403`.
6. The action calls one command or query with the principal and the
   tenant, renders the response, and the transaction commits.
