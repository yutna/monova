# 02 — API contract

The API is REST over JSON. Its contract is an OpenAPI 3.1 document in
YAML, written before the code and kept in the repository (ADR-03).
Request specs check traffic against it (ADR-05), and core's base
controller checks every request against it at runtime. This file says
what the document describes and how every endpoint behaves.

## Rules

### API-01 — Resources, URLs and methods (MUST · ADR-03)

- Every path starts with the major version: `/v1/...` (API-05). The
  root routes mount each product engine under `/v1`, and the engine's
  own routes add its resources: `/v1/invoices`, `/v1/invoices/{id}`.
- A resource name is a plural noun in `snake_case`. Nesting is at most
  one level, and only for a child that cannot exist without its parent:
  `/v1/invoices/{invoice_id}/lines`.
- A path ID is the record's public ID (`04_data.md`), never a sequential
  database ID.
- Methods keep their HTTP meaning: `GET` reads and changes nothing,
  `POST` creates or starts an action, `PATCH` changes the fields it
  sends, `DELETE` removes. `PUT` is not used.

- An action that is not create, read, update or delete is a sub-resource
  created with `POST`: `POST /v1/invoices/{id}/payments`, not
  `POST /v1/invoices/{id}/pay`.
- Request and response bodies are `application/json` in UTF-8. A body
  with another `Content-Type` gets `415`; errors use
  `application/problem+json` (API-08).

### API-02 — JSON shape and casing (MUST · ADR-03)

- Keys are `snake_case`. Every body is a JSON object, never a bare array
  or scalar.
- A single resource is returned under `data`; a collection under `data`
  as an array, with `page` beside it (API-06).
- Every field the schema lists is always present. A field with no value
  is `null`; an empty list is `[]`, never `null`.
- Every resource has `id` and `type` (the singular resource name), and
  `created_at` and `updated_at`.
- Timestamps are RFC 3339 strings in UTC with a `Z` suffix. Dates
  without a time are `YYYY-MM-DD`.
- Money is an object with `amount` as a decimal string and `currency` as
  an ISO 4217 code, never a float.
- Enum values are lowercase `snake_case` strings.
- Clients ignore fields they do not know, so adding a field is not a
  breaking change (API-05).

### API-03 — The document is written first, in engine fragments (MUST · ADR-03)

- Each product engine keeps its part of the document in
  `engines/<engine>/openapi/`: `paths.yaml` for its operations and
  `schemas/` for its schemas. Core keeps the shared parts (problem
  details, the page object, money, the shared parameters and error
  responses) in `engines/core/openapi/`.
- The root `openapi/v1.yaml` holds the `info` and the security scheme.
  Fragments name paths without the version; the root lists each path
  with its `/v1` prefix and refers to the engine's path item with
  `$ref`, so the bundle holds the paths that requests use.
- Redocly CLI (`redocly bundle`) resolves those references into one
  committed file, `openapi/v1.bundle.yaml`. The application and the
  specs load only the bundle, never the fragments. CI bundles again and
  fails when the result differs from the committed file.
- `redocly lint` runs on the root document in CI.
- Every operation has an `operationId` of the form
  `<engine>_<verb>_<resource>` (`billing_list_invoices`), one tag named
  after its engine, its required scopes (`03_identity_access.md`), and
  every response it can return, errors included.
- Request schemas set `additionalProperties: false`, so an unknown field
  is rejected instead of ignored.
- An endpoint change edits the YAML first, in the same pull request as
  the code. Generators create the fragment, the request spec and the
  controller together (`11_generators.md`).

### API-04 — Requests and responses are checked against it (MUST · ADR-05)

- At runtime, core's base controller validates each request against the
  bundle with `openapi_first` before the action runs. A failure renders
  a problem (API-08) through a custom `OpenapiFirst::ErrorResponse`, so
  a validation failure has the same shape as every other error.
- Request specs wrap the application with the `openapi_first` test
  helpers, which validate every request and response against the
  bundle. An undocumented request, response status or query parameter
  fails the spec. The helpers ignore undocumented `401`, `404` and `500`
  responses by default; the setup removes those exceptions.
- The helpers' coverage report runs with a minimum of 100%, so every
  documented response has a spec that produces it. A response that no
  spec can reach is removed from the document.
- Responses are not validated at runtime in production.

### API-05 — Versions change only by adding (MUST · ADR-03)

Within a major version, only additive changes are allowed: a new
endpoint, an optional request field or parameter, a new response field,
a new error code, or a new enum value where the schema says the list is
open.

Everything else is breaking: removing or renaming anything, changing a
type or a format, making an optional input required, tightening a
validation, or changing what a status or an error code means. A breaking
change ships as `/v2` beside `/v1`; both run until `/v1` is retired.
CI compares the bundle with the one on `main` and fails on a breaking
change inside a version; `12_enforcement.md` names the tool.

Retiring an operation or a version:

1. Mark it `deprecated: true` in the document.
2. Every response from it carries `Deprecation` (RFC 9745, a structured
   date such as `@1798761600`), `Sunset` (RFC 8594, an HTTP date) and
   `Link: <...>; rel="deprecation"` to the migration notes.
3. Remove it only after the sunset date. The notice period SHOULD be at
   least six months; each application records its own in an ADR.

### API-06 — Collections use cursor pagination (MUST · ADR-03)

- A collection takes `limit` (default 25, maximum 100) and `cursor`.
  Offset pagination is not offered, because it skips or repeats rows
  when data changes between pages.
- The response carries `page` with `next_cursor` and `has_more`;
  `next_cursor` is `null` on the last page. There is no total count; an
  endpoint that needs one documents a separate count operation.
- The cursor is opaque to clients: core encodes the sort key values of
  the last row and its ID, and signs it, so a client cannot build or
  change one. It is bound to the filter and sort it was made for.
- The order is always total: the sort key plus the ID as a tie-breaker.
- A cursor that does not verify, or that is used with another filter or
  sort, gets `400` with the code `invalid_cursor`.
- Core's pagination helper (ARCH-03) does this; an engine does not write
  its own.

### API-07 — Filter and sort only on documented fields (MUST · ADR-03)

- Filters are query parameters in the form `filter[<field>]=<value>`,
  documented as a `deepObject` parameter whose schema lists every
  allowed field and sets `additionalProperties: false`.
- Sort is `sort=<field>` or `sort=-<field>` for descending, with the
  allowed fields listed as an enum. Each endpoint documents its default
  order.
- A field is allowed only when a query object supports it and an index
  backs it (`07_performance.md`). Free-text search is its own
  documented parameter, not a filter.
- An unknown filter or sort field gets `400` from the request check
  (API-04), never silently ignored.

### API-08 — Errors are problem details (MUST · ADR-03)

Every error response is an RFC 9457 problem with the media type
`application/problem+json`, rendered by core's error responder
(ARCH-03):

```json
{
  "type": "https://api.acme.example/problems/validation_failed",
  "title": "Validation failed",
  "status": 422,
  "detail": "The invoice could not be saved.",
  "code": "validation_failed",
  "request_id": "6f1c2e0a-3b7d-4c9e-8f21-5a0b9d4e7c13",
  "errors": [
    { "pointer": "/total/amount", "code": "blank",
      "message": "can't be blank" }
  ]
}
```

- `type` is a stable URI for the code, under the API's documentation.
  `about:blank` is not used.
- `title` is fixed for the code; `detail` explains this occurrence.
  Both come from the owning engine's locale files.
- `code` and `request_id` are extension members on every problem.
- `errors` lists field errors, each with a JSON Pointer (RFC 6901) into
  the request body, a code and a message. Validation failures from
  `openapi_first` (API-04) use the same members.
- A problem never contains a stack trace, SQL, a class name, a file path
  or another tenant's data. An unexpected error is a `500` with the code
  `internal_error` and nothing else; the details go to the logs with the
  request ID (`09_observability_ops.md`).
- The `status` member always equals the HTTP status.

### API-09 — One error catalog (MUST · ADR-03)

Core owns the codes every engine shares:

| Code | Status | When |
| --- | --- | --- |
| `invalid_request` | 400 | Malformed body or parameters |
| `invalid_cursor` | 400 | Cursor does not verify (API-06) |
| `idempotency_key_missing` | 400 | Key required but absent |
| `unauthenticated` | 401 | Token missing, unknown or expired |
| `forbidden` | 403 | Scope or policy denies the call |
| `not_found` | 404 | No such record visible to the caller |
| `conflict` | 409 | State conflict, e.g. already paid |
| `idempotency_key_in_use` | 409 | Same key still in progress |
| `precondition_failed` | 412 | `If-Match` does not match |
| `unsupported_media_type` | 415 | Body is not JSON |
| `validation_failed` | 422 | Business validation failed |
| `idempotency_key_reused` | 422 | Same key, different request |
| `precondition_required` | 428 | `If-Match` missing |
| `rate_limited` | 429 | Over the rate limit (API-14) |
| `internal_error` | 500 | Unexpected failure |
| `service_unavailable` | 503 | Maintenance or overload |

- An engine adds its own codes, prefixed with its name
  (`billing_invoice_already_paid`), defined in its fragment and its
  locale files. A code is never reused for another meaning.
- A record that exists but belongs to another tenant, or that the caller
  may not see, gets `404`, not `403` (`03_identity_access.md`).
- Each operation lists the codes it can return in the document, so
  clients can switch on `code`, never on `title` or `detail`.

### API-10 — Unsafe creates take an idempotency key (MUST · ADR-03)

Clients retry after timeouts, so a `POST` that creates a record or has
an effect outside the database requires an `Idempotency-Key` header.
The header follows the IETF draft
`draft-ietf-httpapi-idempotency-key-header` (version 09 when this was
written, not yet an RFC): a structured string, a UUID by convention.

- Core stores the key per token in `core_idempotency_keys`, with a
  fingerprint of the method, path and body, the state, and the response.
  The row is tenant-owned and kept 24 hours.
- A repeat with the same key and fingerprint gets the stored response,
  status and body unchanged, and the action does not run again.
- Missing key: `400` `idempotency_key_missing`. Same key while the first
  request runs: `409` `idempotency_key_in_use`. Same key with another
  fingerprint: `422` `idempotency_key_reused`.
- `GET`, `PATCH` with `If-Match` (API-11) and `DELETE` are already safe
  to retry and take no key.

### API-11 — Conditional requests and optimistic locking (MUST · ADR-03)

- A record that can change has a `lock_version` column, so Active Record
  optimistic locking guards concurrent writes.
- `GET` of a single resource returns a strong `ETag` built from the
  record's ID and `lock_version`, using `stale?` with `strong_etag:`.
  `If-None-Match` with the current tag gets `304`. Rails tags are weak
  by default, and a weak tag cannot answer `If-Match`.
- `PATCH` and `DELETE` require `If-Match`. Rails does not check it, so
  core does: missing gets `428` `precondition_required`; a tag that does
  not match gets `412` `precondition_failed`. A stale write that slips
  past the check raises `ActiveRecord::StaleObjectError`, which core
  also renders as `412`.
- A successful write returns the new `ETag`.
- Collections MAY return a weak `ETag`. Cache headers for authenticated
  responses are set in `07_performance.md`.

### API-12 — Long work answers 202 with an operation (SHOULD · ADR-03)

Work that may take longer than the request budget (`07_performance.md`)
runs in a job (`06_async_integration.md`) instead of the request:

- The endpoint answers `202 Accepted` with `Location:
  /v1/operations/{id}` and the operation in the body.
- Core owns the operation resource, its table `core_operations` and its
  route, which the root mounts under `/v1` like a product engine's. An
  operation is tenant-owned and readable only with the token's tenant.
- An operation has `status` (`pending`, `running`, `succeeded`,
  `failed`), `created_at`, `updated_at`, and on completion either
  `result_url` to the resource it produced or `error` as a problem
  (API-08).
- `GET /v1/operations/{id}` returns it with `Retry-After` while it is
  not finished. Finished operations are kept 7 days.
- A `POST` that answers `202` takes an idempotency key (API-10), so a
  retry returns the same operation.

### API-13 — No CORS by default (MUST · ADR-02)

Clients are apps and machines, and a browser front end calls its own
backend, which holds the token (ADR-02). The application therefore sends
no CORS headers and answers no preflight requests. An application that
must serve a browser directly records the decision in an ADR and allows
exact origins only, never `*`, and never with credentials.

### API-14 — Rate limits are visible to clients (MUST · ADR-03)

The limits themselves are set in `08_security.md`. When a request is
over a limit:

- the response is `429` with the code `rate_limited` and a `Retry-After`
  header in seconds;
- the error responder renders it as a problem like any other error,
  including the `429` that Rails `rate_limit` raises.

Responses SHOULD also carry `RateLimit-Policy` and `RateLimit` from the
IETF draft `draft-ietf-httpapi-ratelimit-headers` (version 12 when this
was written, not yet an RFC). Because it is a draft, clients must not
depend on these headers; `Retry-After` is the contract.
