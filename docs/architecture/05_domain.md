# 05 — Domain

Active Record models keep their own invariants; value, command and
query objects carry the rest of the domain logic, and there are no
repository classes (ADR-09). Engines reach each other only through
public commands, queries and events (ADR-08). Events leave a command
through a transactional outbox, so a subscriber sees an event exactly
when the change behind it is committed (ADR-22).

## Terms

| Term | Meaning |
| --- | --- |
| Value object | An immutable `Data` class compared by its values |
| Command | Changes state for one use case; one public `call` |
| Query | Reads state for one use case; never writes |
| Unit of work | The tenancy helper's transaction (AUTH-09) |
| Domain event | A named fact a command recorded about a change |
| Outbox | `core_outbox_events`, where commands record events |
| Subscriber | A handler in another engine that reacts to an event |

## Rules

### DOM-01 — Each kind of logic has one home (MUST · ADR-09)

| Logic | Kind | Folder in the engine |
| --- | --- | --- |
| HTTP to a call and back | Controller | `app/controllers/` |
| Who may do what | Policy (AUTH-06) | `app/policies/` |
| Invariants of one record | Model | `app/models/` |
| A concept with no identity | Value object | `app/values/` |
| A change for one use case | Command | `app/commands/` |
| A read for one use case | Query | `app/queries/` |
| The JSON of a resource | Serializer (API-02) | `app/serializers/` |
| A reaction to an event | Subscriber | `app/subscribers/` |
| Work that runs later | Job (`06_async_integration.md`) | `app/jobs/` |
| A call to an outside service | Client (INT-08) | `app/clients/` |

- A command, query or value object that other engines may use lives in
  `app/public/` instead (ARCH-06), in the same namespace, so moving it
  there does not rename it.
- Core's base classes, `Acme::Core::Command`, `Acme::Core::Query` and
  the shared value objects such as `Acme::Core::Money`, live in
  `engines/core/app/public/` (ARCH-03).
- Code that fits none of these rows is a sign that a row is being
  avoided; it is not a reason for a `services/` or `lib/` folder.

### DOM-02 — Models hold invariants, not workflows (MUST · ADR-09)

- A model declares its associations inside its engine (ARCH-07), its
  validations, which mirror constraints (DATA-07), its scopes, and
  methods that read or derive its own attributes.
- A callback may only set or normalize the record's own attributes.
  A callback never changes another record, enqueues a job, sends
  mail, records an audit or domain event, or calls out of the process;
  those steps belong to the command, where the use case is visible.
- A model never reads `Current` (AUTH-10) and never calls a command.
- A model method that needs a second model, a policy or another engine
  is a command or a query.

### DOM-03 — Value objects are immutable Data classes (MUST · ADR-09)

- A value object is a Ruby `Data` class (`Data.define`): no setters,
  equal when its class and every member are equal. A mutable member,
  such as an array, is frozen in `initialize`.
- `initialize` takes keyword arguments, converts and checks them, and
  raises `ArgumentError` for a value that cannot exist, so an invalid
  instance never does.
- A value object does no I/O: no query, no clock read, no HTTP call.
  A current time or a looked-up rate is passed in.
- A model exposes columns that form one value through a reader and a
  writer that build and split the value object. `composed_of` is not
  used, because its `class_name:` string hides the reference from
  Packwerk (ARCH-08).

`Acme::Core::Money` is the money value of DATA-09: a `BigDecimal`
amount and an ISO 4217 currency code. Adding, subtracting or comparing
two amounts in different currencies raises; rounding takes the
rounding mode as an argument; `as_json` returns the API object of
API-02. Engines use it for every money value and define no other.

### DOM-04 — A command is one use case with one entry point (MUST · ADR-09)

```ruby
# engines/billing/app/commands/acme/billing/void_invoice.rb
module Acme::Billing
  class VoidInvoice < Acme::Core::Command
    def call(principal:, tenant:, invoice:, reason:)
      if invoice.paid?
        raise Acme::Core::Conflict, :billing_invoice_already_paid
      end

      invoice.update!(status: "voided", void_reason: reason)
      audit("billing.invoice.voided", invoice,
            changed: %i[status void_reason])
      publish(Events::INVOICE_VOIDED, invoice)
      invoice
    end
  end
end
```

- A command is named verb first (`VoidInvoice`) and is called as
  `VoidInvoice.call(...)`. The class method builds an instance and
  calls `#call`; there is no other public method.
- It takes the principal and the tenant as keyword arguments
  (AUTH-10), plus the records the caller has already loaded and
  authorized (AUTH-08) and plain inputs or value objects. It never
  takes `params` or a request.
- It returns the changed record, or a value object when it is public
  (ARCH-06). It does not render and does not choose an HTTP status.
- A controller action calls exactly one command or one query. A
  command may call queries and the public commands of engines its
  engine depends on (DOM-12).

### DOM-05 — The unit of work is the tenancy transaction (MUST · ADR-09)

- A command runs inside the tenancy helper's transaction (AUTH-09),
  which the base controller opens for the whole action and the base job
  opens around `perform` (AUTH-11). A command that runs with no tenant
  set finds no rows and fails; it does not open its own tenant.
- A command does not open a savepoint (`requires_new: true`) and does
  not commit. A nested `transaction` block joins the outer transaction,
  so every write of the command, of the commands it calls, and its
  audit (DATA-14) and outbox records commit together or not at all.
- Writes use the raising methods (`save!`, `update!`, `create!`,
  `destroy!`), so a failed write aborts the unit of work.
- A command makes no call outside the database: no outbound HTTP, no
  mail, no direct enqueue into another database. Such an effect is a
  subscriber (DOM-11) or a job of its own engine.
- Core's base job sets `self.enqueue_after_transaction_commit = true`,
  so a job a command enqueues is pushed only after the unit of work
  commits and is dropped when it rolls back. Rails 8.1 accepts only a
  boolean here; engines do not change it.

### DOM-06 — Expected failures raise core's domain errors (MUST · ADR-03)

There is one error path, and it ends in core's error responder
(API-08). Commands do not return result objects.

- A broken business rule raises a subclass of `Acme::Core::DomainError`
  with an error code from the catalog (API-09): `Conflict` for a state
  conflict (`409`), `Invalid` for a business validation (`422`) with
  field errors, `NotFound` for a referenced record the caller may not
  see (`404`).
- Invalid records raise `ActiveRecord::RecordInvalid` from the raising
  writes; core renders it as `422` `validation_failed` with field
  errors.
- The exception leaves the tenancy helper, which rolls back the unit of
  work, and core's error responder renders it. Nothing is rescued in
  an engine to be turned into a status.
- A job that meets a domain error does not retry it; the retry rules
  for other errors are in `06_async_integration.md`.

### DOM-07 — Queries read through the caller's scope (MUST · ADR-06)

- A query is named for what it returns (`OverdueInvoices`,
  `CustomerBalance`) and is called as `Query.call(...)` with the
  principal and the tenant as keyword arguments (AUTH-10).
- A query that returns records starts from the policy scope for the
  principal (AUTH-06, AUTH-08), never from a bare model class, and
  returns a relation, so the controller can paginate it (API-06) and
  preload what the serializer needs (`07_performance.md`).
- A public query returns value objects or arrays of them, never a
  relation or a model (ARCH-06).
- A query never writes, enqueues or records an event.

### DOM-08 — Lifecycles are states with named transitions (MUST · ADR-09)

- A record with a lifecycle has a `status` text column with a check
  constraint (DATA-07) and an `enum` that lists the states.
- The model declares its allowed transitions as a frozen hash constant,
  from each state to the states it may move to, and a
  `may_transition_to?(state)` reader.
- Only a command changes `status`, one command per transition named for
  it (`VoidInvoice`, `PayInvoice`). A transition the hash does not
  allow raises `Acme::Core::Conflict` with the engine's code.
- Concurrent transitions are stopped by optimistic locking (API-11);
  the losing write is `412`, never a silent overwrite.
- A transition that matters is audited (DATA-14) and, when other
  engines care, published as an event (DOM-09).

### DOM-09 — Events are named facts in a public surface (MUST · ADR-08)

- An event name is `<engine>.<resource>.<past-tense verb>`, such as
  `billing.invoice.voided`, the same form as the audit action
  (DATA-14). It is a constant in the publisher's public surface,
  `Acme::Billing::Events::INVOICE_VOIDED` in
  `app/public/acme/billing/events.rb` (ARCH-08).
- An event carries its ID (UUIDv7, DATA-08), its name, a payload
  version, the tenant ID, the principal's type and ID, `occurred_at`,
  the subject's type and ID, and `data` with IDs and `internal` values
  only (DATA-11, DATA-13).
- A payload changes only by adding members. A removed or changed member
  is a new version, published beside the old one until no subscriber
  reads it.
- A subscriber depends on the publisher and declares it in its
  `package.yml` (ARCH-04). So a product engine can react to a domain
  engine's event, and a domain engine never reacts to a product
  engine's event (ARCH-02).
- Domain events are not `ActiveSupport::Notifications` or Rails 8.1's
  event reporter (`Rails.event`); those carry instrumentation for
  logs and traces (`09_observability_ops.md`) and are not durable.

### DOM-10 — Events leave through the transactional outbox (MUST · ADR-22)

- A command publishes with core's `publish`, which inserts a row in
  `core_outbox_events` in the same unit of work. The table is
  tenant-owned (DATA-03), so the event exists exactly when the change
  is committed. Like the audit recorder, the outbox recorder reads the
  principal and the request ID from `Current`; the command passes only
  the name, the subject and the data.
- After the unit of work commits, core uses
  `ActiveRecord.after_all_transactions_commit` to enqueue a relay job
  for that tenant. A rollback drops both the row and the relay job.
- The relay job runs in the tenancy helper for its tenant (AUTH-11),
  reads that tenant's undispatched events in ID order, enqueues one
  delivery job for each subscriber of each event, and marks the event
  dispatched.
- A recurring system job, every five minutes, enqueues one relay job
  per tenant from `core_tenants`, so an event whose relay was lost is
  still dispatched. No relay reads events of two tenants (AUTH-12).
- Delivery is at least once and in no guaranteed order. Dispatched
  events and their deliveries are kept 7 days, then purged per tenant
  (DATA-15).

### DOM-11 — Each subscriber runs once per event (MUST · ADR-22)

- Each engine lists its subscriptions in one autoloaded class,
  `Acme::<Engine>::Subscriptions` in `app/subscribers/`, which maps
  event constants to subscriber classes, so Packwerk sees every
  dependency. The engine registers the list with core at boot, so core
  names no engine constant.
- A delivery job runs in the tenancy helper for the event's tenant. It
  first inserts the pair of event ID and subscriber into
  `core_event_deliveries`, which has a unique index on the pair, and
  then calls the subscriber in the same unit of work. A duplicate
  delivery hits the index and does nothing, so the subscriber's
  database changes happen exactly once.
- A subscriber is a thin adapter: it reads the event and calls one
  command of its own engine, with the tenant and the principal the
  event recorded (AUTH-11).
- A subscriber that needs the current state reads it through the
  publisher's public query; it does not trust the order of events.
- An effect outside the database (an email, a webhook, an outbound
  call) is a job of the subscriber's engine with its own idempotency
  key (`06_async_integration.md`).

### DOM-12 — Engines call down and announce up (MUST · ADR-08)

- An engine calls the public commands and queries of the engines it
  depends on, synchronously, inside the caller's unit of work (DOM-05).
  The caller passes the principal and the tenant through.
- An engine that must tell an engine above it, or one it does not
  know, publishes an event (DOM-09) instead of calling it.
- A synchronous call is for a change that must commit with the
  caller's change, or a read the caller needs now. Anything that may
  happen later is an event.
- A public command validates its own inputs and authorizes against its
  own policy; it never trusts that the calling engine has checked.

## A new use case

1. Add the operation to the engine's OpenAPI fragment (API-03).
2. Write the command or the query, its value objects, and the policy
   rule (AUTH-06) in the folders of DOM-01.
3. Add the audit action (DATA-14) and, if other engines react, the
   event constant (DOM-09).
4. Add the controller action that loads, authorizes, calls the command
   or query, and renders.
5. Write the specs at the cheapest level for each piece
   (`10_testing.md`).
