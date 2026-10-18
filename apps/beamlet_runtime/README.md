# Beamlet Runtime persistence

Runtime is ephemeral unless an explicit `Beamlet.Runtime.Persistence` is supplied.
Durable execution uses `beamlet_actions_storage`; it needs no Agent application,
configuration, callback or tables. Loading either library starts no Repo.

Choose `Beamlet.Actions.Storage.Profiles.authority/0` and `journal/0` explicitly
when initializing new datasets with `Beamlet.Storage.Dataset.initialize/2`.
Open existing datasets with the same descriptors; open never migrates. The
provided Repo instances are `Beamlet.Actions.Storage.SQLiteAuthorityRepo`,
`PostgresAuthorityRepo` and SQLite `ExecutorJournalRepo`. Authority and journal
must be separate datasets. Supply each SQLite dataset's isolated `peer_database`.

```elixir
alias Beamlet.Runtime.Persistence
alias Beamlet.Actions.OperationRef
persistence = Persistence.new(
  authority_repo: authority_repo, journal_repo: journal_repo,
  authority_id: authority_id, executor_id: executor_id,
  executor_boot_id: executor_boot_id,
  dispatch_scope_id: nil, dispatch_epoch: nil)
{:ok, %OperationRef{} = ref} = Beamlet.Runtime.submit(operation,
  persistence: persistence, owner: self(), sink: self())
```

The optional dispatch scope UUID and nonnegative epoch must be supplied together.
They fence pending dispatch; they carry no orchestration or authorization metadata.
`owner:` on `submit/2` remains a PID lifecycle monitor. Persistence has no persistent
owner field.

For a caller-owned atomic preparation, use
`Beamlet.Actions.Storage.OperationRecords.prepare_in_transaction/2`. It validates
the request and attempt and requires an already-open Repo transaction. Roll back
that outer transaction on any participant error. The standalone `prepare/2`
facade rolls back failures itself. Pass the committed preparation response as
`prepared:` to `Runtime.submit/2`; no additional preparation occurs.

The preparation response has string keys `operation_id`, `attempt_id`,
`description_digest`, `attempt_version`, `lock_version`, `dispatch_state`,
`dispatch_scope_id` and `dispatch_epoch`. Runtime verifies the full immutable
request, stored scope and expected scope, digest, versions, exact attempt,
executor and boot, prepared state and absence of an accepted Result. Changing the
payload or substituting another attempt fails before dispatch.

The canonical description fixes kind, protocol version, payload, budget, claims
and safety metadata (metadata/capabilities/environment/allowed nodes). All
logical request parameters belong in that description before preparation.
Credentials remain transient invocation overrides: counted in the wire envelope,
forwarded to the handler, omitted from persisted descriptions and receipts.

A coordinator claims prepared → send_claimed before admission. PostgreSQL holds
the scope FOR SHARE before locking the Operation FOR UPDATE; rotation takes the
scope FOR UPDATE. SQLite immediate write transactions serialize these steps.
Rotation committed first refuses old pending dispatch with `:stale_epoch`.
A claim committed first retains its claimed semantics. Rotation cannot undo a
network send or terminate an existing worker. Explicit pending continuation may
use `DispatchScopes.reauthorize_in_transaction/2`; it cannot reauthorize claimed
or accepted work. There are no automatic business retries.

The gateway records start intent in its local journal before starting a worker.
Terminal attachments and receipt commit together; authority evidence and the
unique accepted Operation Result commit before sink completion. Duplicate claims
never authorize a second worker. Unknown commits do not authorize another send.
After restart, unfinished journal intents become `unknown_after_restart`; this
never means the work did not execute. Late evidence can be retained without
replacing an accepted Result.

`Runtime.evidence(persistence, operation_id, attempt_id)` is read-only, validates
attempt binding, and returns `%{authority: stored_rows, journal: row | :not_found |
:unavailable}`. Both absence and unavailability are inconclusive about execution.
Orchestration consumption belongs to the embedding caller.
