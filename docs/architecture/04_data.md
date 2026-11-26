# 04 — Data

All data lives in PostgreSQL (ADR-04). The schema is owned by one role
and used by another, so the row-level security that keeps tenants apart
(ADR-07, AUTH-09) holds for everything the application runs. The
database enforces what it can: constraints, not only validations
(ADR-09). Personal data is classified, encrypted where it is sensitive,
kept out of logs and deleted on schedule (ADR-21).

## Terms

| Term | Meaning |
| --- | --- |
| Tenant-owned table | Has `tenant_id` and a forced RLS policy |
| Global table | `core_tenants` or `core_users`; no tenant |
| Migrator role | The role that owns the schema and runs migrations |
| Runtime role | The role the application connects as |
| Authentication role | Owns the two pre-tenant lookup functions |
| Data class | `public`, `internal`, `personal`, `sensitive` or `secret` |
| Expand and contract | Schema steps that each work with old and new code |

## Rules

### DATA-01 — Five roles separate ownership from use (MUST · ADR-07)

Every database role and what it may do:

| Role | Login | `BYPASSRLS` | Owns | Used for |
| --- | --- | --- | --- | --- |
| `acme_migrator` | yes | yes | schema and tables | migrations, backfills |
| `acme_app` | yes | no | nothing | the application |
| `acme_auth` | no | no | lookup functions | the AUTH-07 lookups |
| `acme_purge` | no | no | purge function | audit retention |
| `acme_backup` | yes | yes | nothing | backups |

- `acme_app` gets `SELECT`, `INSERT`, `UPDATE` and `DELETE` on tables,
  and `EXECUTE` on the lookup functions. `acme_auth` gets `SELECT` on
  `core_tokens` and `core_machine_clients` only. `acme_purge` gets
  `SELECT` and `DELETE` on `core_audit_events` only. `acme_backup` is a
  member of `pg_read_all_data` and writes nothing.

- No role is a superuser. Superusers and roles with `BYPASSRLS` skip
  every policy, and a table owner skips them unless the table forces
  row-level security; that is why the runtime role owns nothing.
- `acme_migrator` has `BYPASSRLS` because `FORCE ROW LEVEL SECURITY`
  binds the owner too, and a migration or backfill must see every
  tenant's rows. `acme_backup` has it because `pg_dump` turns
  `row_security` off and fails for a role the policies bind
  (`09_observability_ops.md`). These are the only two (AUTH-12).
- The application holds only the `acme_app` credentials. The release
  step that runs migrations gets the migrator credentials; no web or
  job process ever has them (`09_observability_ops.md`).
- `acme_auth` owns the two `SECURITY DEFINER` functions of AUTH-07,
  and `acme_purge` owns the audit purge function (DATA-14). `EXECUTE`
  on each is revoked from `PUBLIC` and granted to `acme_app` only.
- `acme_migrator` is a member of `acme_auth` and `acme_purge`, so a
  migration can hand them their functions with
  `ALTER FUNCTION ... OWNER TO`, which needs that membership and
  `CREATE` on the schema for the new owner. That `CREATE` widens
  nothing: the two roles cannot log in, and their only member already
  owns the schema.
- `core_audit_events` grants `acme_app` only `SELECT` and `INSERT`
  (DATA-14).
- The Solid Queue, Solid Cache and Solid Cable databases (ADR-04) are
  owned by `acme_migrator` and used by `acme_app` the same way. They
  hold no tenant-owned table, so they have no row-level security; job
  arguments carry IDs, never `personal`, `sensitive` or `secret` values
  (DATA-11).
- `acme` stands for the application namespace, like `Acme`; adopters
  rename the roles with it.

### DATA-02 — One re-runnable script creates the roles and grants (MUST · ADR-07)

- `bin/db-roles` creates the five roles and their grants in every
  database, for development, CI and each deployed environment. Running
  it again changes nothing that is already right, so it is safe after
  every release.
- It creates a missing role, and resets the attributes of an existing
  role (`NOSUPERUSER`, `BYPASSRLS` or `NOBYPASSRLS`, `LOGIN` or
  `NOLOGIN`) to the table in DATA-01, so a role that drifted is
  corrected rather than trusted.
- It grants with `ALTER DEFAULT PRIVILEGES FOR ROLE acme_migrator`, for
  tables (`SELECT, INSERT, UPDATE, DELETE`) and sequences
  (`USAGE, SELECT`), so a table a later migration creates is usable at
  once. It also grants on existing objects, for a database restored
  from a dump, and as its last step revokes `UPDATE` and `DELETE` on
  `core_audit_events` from `acme_app` again, so a rerun never undoes
  DATA-14.
- Passwords come from the environment of the run, never from the
  script or the repository (`08_security.md`).
- A kernel spec connects as `acme_app` and proves that the role owns no
  table, has neither `BYPASSRLS` nor superuser rights, cannot run DDL
  and cannot update or delete an audit event (`10_testing.md`).

### DATA-03 — Tenant-owned tables carry tenant_id and a forced policy (MUST · ADR-07)

- Every table except the two global tables (AUTH-07) and Rails'
  internal tables (`schema_migrations`, `ar_internal_metadata`) is
  tenant-owned.
  Its migration creates `tenant_id uuid NOT NULL`, a foreign key to
  `core_tenants`, and an index that starts with `tenant_id`. Every
  unique index on the table includes `tenant_id`.
- The `tenant_id` column defaults to the transaction's tenant setting
  (AUTH-09), so an insert inside the tenancy helper fills it. Models
  declare it `attr_readonly` and never assign it.
- The same migration calls core's helper
  `add_tenant_policy :billing_invoices`, which enables and forces row
  level security and creates the policy of AUTH-09 for both `USING`
  and `WITH CHECK`. A tenant-owned table is never created without it.
- Engine models inherit `Acme::Core::ApplicationRecord`, the abstract
  base record in core (ARCH-03). Tenant-owned models include core's
  `TenantOwned` concern, which marks `tenant_id` read-only and declares
  no `default_scope`: row-level security filters rows, and policies
  narrow them further (AUTH-08).
- A kernel spec reads the catalog and fails when a table with
  `tenant_id` lacks a forced policy, or a table without it is not a
  global table or a Rails internal table (`10_testing.md`).

### DATA-04 — The schema is kept as structure.sql (MUST · ADR-04)

- `config.active_record.schema_format = :sql`. `schema.rb` cannot
  record row-level security policies, functions, grants or check
  constraints written in SQL, so it would load a database without them.
- `db/structure.sql` is committed and regenerated by every migration.
  CI loads it into an empty database and runs the specs there, so a
  policy that exists only in a migration is caught.

### DATA-05 — Migrations are zero-downtime (MUST · ADR-04)

- `strong_migrations` checks every migration in development and CI.
  Core's initializer sets `lock_timeout` to 10 seconds,
  `statement_timeout` to one hour, `target_version` to the pinned
  PostgreSQL major version, and turns on `check_down`,
  `auto_analyze`, `alphabetize_schema` and `remove_invalid_indexes`.
- A deploy runs migrations while the old code still serves requests,
  so every change works with both versions (expand and contract):
  - add an index with `algorithm: :concurrently` and
    `disable_ddl_transaction!`;
  - add a foreign key or a check constraint with `validate: false`,
    and validate it in a later migration;
  - make an existing column `NOT NULL` through a validated check
    constraint first;
  - remove a column by adding it to `ignored_columns`, deploying, and
    removing it in a later release;
  - rename a column or change its type through a new column, writes to
    both, a backfill, then the removal of the old one.
- `safety_assured` is allowed only with a comment that says why the
  operation is safe; review checks the reason.
- Every migration can be reversed: `change` with reversible steps, or
  `up` and `down`. A migration that cannot be reversed raises
  `ActiveRecord::IrreversibleMigration` in `down` and says why.
- Engine migrations stay in their engine (ARCH-07).

### DATA-06 — Data changes run apart from schema changes (SHOULD · ADR-07)

- A migration changes the schema. Backfilling or correcting rows runs
  as a separate task after the migration has deployed, in batches,
  each batch in its own transaction, so it never holds locks across
  the whole table.
- A backfill that works through application code runs as `acme_app`
  through the tenancy helper, one tenant at a time (AUTH-12). A
  backfill in plain SQL MAY run as `acme_migrator`; it touches only the
  columns it changes and is reviewed like a migration.
- A small backfill on a new or tiny table MAY live in its migration.

### DATA-07 — Constraints first, validations mirror them (MUST · ADR-09)

- Every invariant the database can express is a constraint: `NOT NULL`
  for a required column, a foreign key for every reference to a table
  the engine may reach (ARCH-07), a unique index for every uniqueness,
  a check constraint for ranges and formats.
- A model validation mirrors a constraint so the client gets a
  `422` with a field error (API-08) instead of a database error. A
  uniqueness validation never stands alone: the unique index decides,
  and core turns `ActiveRecord::RecordNotUnique` into the same `422`.
- A reference to a table of an engine outside the declared
  dependencies is a plain `uuid` column with no foreign key; the owning
  engine's command keeps it valid (ARCH-07).
- An enum is a `text` column with a check constraint that lists its
  values, declared with Rails `enum` mapping each value to its own
  string. Integer enums are not used; the stored value equals the API
  value (API-02).
- Columns default to `NOT NULL`. A nullable column means "unknown or
  not applicable", and its schema says so.

### DATA-08 — Primary keys are UUIDv7 and are the public ID (MUST · ADR-04)

- Every table's primary key is `id uuid` with the database default
  `uuidv7()`, set by core's table helper. Every foreign key, including
  `tenant_id`, is a `uuid`. No table has a sequential ID.
- The `id` is the public ID: it is the `id` of the resource (API-02)
  and the ID in paths (API-01). There is no second public ID column.
- UUIDv7 starts with a timestamp, so new rows land at the end of the
  index, like a sequence, while the random part keeps IDs unguessable.
  The cost is that an ID reveals when its row was created; a resource
  for which that matters adds a separate random public ID column in an
  ADR.
- The generators set `primary_key_type: :uuid`, and core's helper sets
  the default, so `create_table` never falls back to `bigint` or to
  random version 4 UUIDs (`11_generators.md`).
- The order of `id` is close to creation order but is not a contract;
  a collection sorts by an explicit column, with `id` as the tie
  breaker (API-06).

### DATA-09 — Money is a decimal amount with a currency (MUST · ADR-03)

- A money value is two columns: `<name>_amount numeric(19, 4) NOT NULL`
  and `<name>_currency text NOT NULL` with a check constraint
  `<name>_currency ~ '^[A-Z]{3}$'`.
- Ruby reads the amount as `BigDecimal` and wraps both columns in
  core's money value object (`05_domain.md`), which renders the API
  object of API-02. A float never holds money, in a column, a variable
  or a JSON number.
- Amounts in different currencies are never added or compared; the
  value object raises instead.
- Rounding happens once, in the command that computes the amount, with
  a rounding mode the domain names.

### DATA-10 — Time is stored with its zone, in UTC (MUST · ADR-04)

- Core sets the PostgreSQL adapter's `datetime_type` to `:timestamptz`,
  so `t.datetime` and timestamps create `timestamp with time zone`
  columns. The application time zone and the database session time
  zone are UTC.
- Code uses `Time.current` and `Date.current`, never `Time.now` or
  `Date.today`; RuboCop's Rails cops check it.
- A calendar date with no time, such as a due date, is a `date`
  column. A local time that must follow a user's zone stores the IANA
  zone name beside it.
- Timestamps end in `_at` and dates in `_on`. Every table has
  `created_at` and `updated_at`.

### DATA-11 — Every column has a data class (MUST · ADR-21)

| Class | Examples | Handling |
| --- | --- | --- |
| `public` | product names, enum values | none |
| `internal` | IDs, flags, amounts | kept inside the tenant |
| `personal` | names, emails, phones, IPs | filtered (DATA-13), erasable |
| `sensitive` | national IDs, bank, health | as `personal`, encrypted |
| `secret` | password and token digests, keys | as `sensitive`, never output |

`personal` data is erased on request (DATA-15), `sensitive` data is
encrypted (DATA-12), and `secret` values are never serialized or
returned.

- Each engine lists the class of every column of its tables in
  `engines/<engine>/db/data_classes.yml`. A kernel spec compares the
  file with `db/structure.sql` and fails when a column is missing,
  so a new column cannot arrive unclassified (`10_testing.md`).
- A column of class `personal` or higher is never copied into another
  engine's table, a job argument, a cache key, an event payload or a
  log line; those carry the record's ID.
- A column whose class is unclear is classed higher, not lower.

### DATA-12 — Sensitive columns use Active Record encryption (MUST · ADR-21)

- Every `sensitive` column, and every `secret` value that must be read
  back (such as an outbound webhook signing key), is declared with
  `encrypts`. Values that are only compared, such as passwords and
  tokens, are stored as digests instead (AUTH-01).
- Encryption is non-deterministic by default. Deterministic encryption,
  which allows `where` and unique indexes, cannot rotate its key, so it
  is used only with an ADR.
- A `personal` column that must be found or kept unique, such as
  `core_users.email`, is encrypted non-deterministically and gets a
  sibling `<name>_digest` column: an HMAC-SHA256 of the normalized
  value with a key from the credentials, with a unique index. Lookups
  use the digest. Normalizing (for an email address: strip and
  downcase) happens in one place, with Rails `normalizes`.
- The keys (`active_record_encryption.primary_key`,
  `deterministic_key`, `key_derivation_salt`) and the digest keys live
  in the Rails credentials of each environment
  (`08_security.md`). Old keys stay listed under `previous` until every
  row is re-encrypted.
- `support_unencrypted_data` stays `false`, except during a migration
  that encrypts an existing column, and is turned off in the release
  after the backfill.

### DATA-13 — Logs and errors never contain personal or secret values (MUST · ADR-21)

- `config.filter_parameters` keeps every entry of the Rails default
  list (`passw`, `email`, `secret`, `token`, `_key`, `crypt`, `salt`,
  `certificate`, `otp`, `ssn`, `cvv`, `cvc`) and adds the names of
  every `personal`, `sensitive` and `secret` column that the defaults
  miss. An entry is never removed.
- `filter_attributes` follows `filter_parameters`, so `inspect` on a
  record hides those columns too, and encrypted attributes are added
  automatically. Error reports and traces use the same filter
  (`09_observability_ops.md`).
- Production logs at the `info` level, which does not log SQL
  statements or their bound values.
- A request spec in core sends filtered parameters and fails when any
  of them reaches the log (`10_testing.md`).

### DATA-14 — Changes that matter leave an audit event (MUST · ADR-21)

- `core_audit_events` is a tenant-owned table in core: `occurred_at`,
  the principal type and ID, the token ID, the request ID, an `action`
  such as `billing.invoice.voided`, the subject type and ID, the names
  of the changed attributes, and `metadata` as `jsonb`.
- The command that makes a change records its event through core's
  audit recorder, in the same transaction, so the event exists exactly
  when the change does. The recorder reads the principal, the token
  and the request ID from `Current` (AUTH-10); commands do not pass
  them.
- An event records attribute names, never values of class `personal`
  or higher. `metadata` holds IDs and `internal` values only.
- Each engine audits at least: creating and deleting a resource, a
  change of state, a change of who may access something, and every
  action an issue or ADR marks as audited. Core audits sign-in, token
  issue and revocation, membership and machine client changes.
- The table is append-only: `acme_app` has no `UPDATE` or `DELETE` on
  it (DATA-01). Old events are deleted only by core's purge function,
  `SECURITY DEFINER` and owned by `acme_purge`, which takes no
  arguments and deletes only events older than the retention period
  (DATA-15). Row-level security still binds it, so the retention job
  calls it inside the tenancy helper, one tenant at a time.

### DATA-15 — Data is kept only as long as its retention says (MUST · ADR-21)

| Data | Kept for |
| --- | --- |
| Expired and revoked tokens | 30 days (AUTH-03) |
| Audit events | 1 year |
| Finished Solid Queue jobs | 1 day (`clear_finished_jobs_after`) |
| A deleted tenant's rows | 30 days after the deletion, then erased |
| Backups | `09_observability_ops.md` |

- An application MAY change these periods in an ADR. A period for a
  new kind of data is set by the issue that introduces it, in
  `data_classes.yml` beside its columns.
- Recurring jobs delete expired rows in batches, one tenant at a time
  (AUTH-11).
- Erasing a person replaces their `personal` and `sensitive` columns
  with placeholders or deletes the rows, and records an audit event
  without the erased values. Audit events keep the principal ID, which
  no longer resolves to a person.
- Deletion is real by default. A resource that needs undo or history
  adds a `discarded_at` column in its own issue; no soft-delete gem is
  installed for every model.

### DATA-16 — Seeds are idempotent and synthetic (SHOULD · ADR-17)

- `db/seeds.rb` loads each engine's `engines/<engine>/db/seeds.rb` in
  dependency order (ARCH-04). Each uses `find_or_create_by!`, so
  `bin/rails db:seed` can run any number of times.
- Seeds create a development tenant, a user, a client app and sample
  rows through the engines' commands, inside the tenancy helper, so
  they obey the same policies as the application.
- Seed data is invented. Real personal data, production dumps and real
  credentials never enter seeds, fixtures or factories.
- Production runs no seeds. A tenant or user in production is created
  through a task or the API.

## A new tenant-owned table

1. Classify each column in the engine's `data_classes.yml` (DATA-11).
2. Create the table with core's helpers: UUIDv7 `id` (DATA-08),
   `tenant_id` with its index and foreign key, and
   `add_tenant_policy` (DATA-03).
3. Add the constraints first, then the validations that mirror them
   (DATA-07); `encrypts` for sensitive columns (DATA-12).
4. Run the migration; `strong_migrations` passes (DATA-05) and
   `db/structure.sql` is regenerated (DATA-04).
5. The kernel specs for row-level security, data classes and grants
   pass without changes to them.
