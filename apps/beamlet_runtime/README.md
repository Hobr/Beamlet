# Runtime durable integration (authority format 2)

Runtime is opt-in and starts no Repo. Ownerless `Runtime.submit(operation,
persistence: persistence)` commits one immutable generic Operation and one prepared
attempt. Without persistence, the existing ephemeral path applies.

Owned model/tool/summary requests must first use
`Beamlet.Storage.AgentRecords.prepare_operations/2`. Build the exact
`Beamlet.Actions.Operation` first and store `Persistence.description(operation)`
in each member, with its ordered `sources`, Agent/turn/step/role/ordinal and one
executor/boot-bound attempt. See [Storage API](../beamlet_storage/README.md).

```elixir
{:ok, committed} = AgentRecords.prepare_operations(repo, %{
  command_id: command_id,
  position: %{agent_id: agent_id, lock_version: version, generation: generation},
  turn_id: turn_id,
  operations: [%{
    operation: %{
      id: operation_id, owner_agent_id: agent_id, turn_id: turn_id,
      step_id: step_id, role: "model", ordinal: 0,
      description: Persistence.description(operation), sources: sources
    },
    attempt: %{
      attempt_id: attempt_id, executor_id: persistence.executor_id,
      executor_boot_id: persistence.executor_boot_id,
      budget: %{"budget_ms" => operation.budget_ms}
    }
  }],
  orchestration: %{}
})
{:ok, ref} = Runtime.submit(operation,
  persistence: persistence, prepared: hd(committed["operations"]),
  owner: owner_pid, sink: sink_pid, require_live_owner: true)
```

The `prepared:` map has string keys `operation_id`, `attempt_id`,
`description_digest`, `attempt_version`, `lock_version`. Runtime fetches the
committed row and verifies the complete description, versions, exact attempt,
executor and boot, prepared state and absent accepted Result before starting a
Coordinator. It never prepares another row for this path. Optional Persistence
`owner: %{agent_id: uuid, turn_id: uuid, step_id: string}` additionally checks that
binding; it is identity metadata only and cannot create owned work. Agent versions
and acceptance sequence reservations have no Runtime API.

The canonical description fixes kind, protocol version, payload, budget, claims,
and safety metadata (Operation metadata/capabilities/environment/allowed nodes).
Put all effective logical provider parameters, model identifiers, schemas, tool
arguments and effective nonsecret configuration in payload **before** preparation;
policy/source transformation metadata can be fixed in Operation metadata. Storage
owns validated ordered sources. Runtime does not resolve or mutate provider
requests. Executor-local Handler settings are trusted infrastructure, may contain
live observer PIDs, and must not serve as the sole copy of logical model options.
Credentials are the only transient invocation override: validated and counted in
the full wire envelope, forwarded unchanged, omitted from description, receipts,
Results and ordinary observations. No secure memory erasure is promised.

One Coordinator claims prepared→send_claimed before selection/admission. A failed
or duplicate claim exits without a Result write or sink completion. A lost claim
acknowledgement never authorizes a send. A completed preparation command replay is
not dispatch permission. Old Agent generations fail Storage's claim check; C must
retire old senders at activation, including a sender that claimed before activation.

Local and named peers use the same Gateway protocol. Gateway recomputes the
canonical digest and commits start_intent before a Worker exists. Only an explicit
journal not-found permits initial journal insertion; unavailable does not. Terminal
receipt commits before notification; authority evidence and independent Operation
acceptance commit before sink completion. Receipt digest and all identity bindings
are validated. Unknown acceptance commits are reconciled by stable Operation ID,
without write retry. Failed acceptance hides the Result from status and sink.

Authority and executor journal commits are separate transactions. A claim without
an observed admit remains unknown; a start_intent after restart becomes
unknown_after_restart. Neither permits another Worker. No automatic business retry,
replay or failover exists. Late correlated receipts can add evidence but never
replace an accepted Result or trigger a second completion. First stop cause and
actual termination classification remain Gateway-owned.

`Runtime.evidence(persistence, operation_id, attempt_id)` is read-only and validates
attempt binding. It returns `%{authority: stored_rows, journal: row | :not_found |
:unavailable}`. Both journal absence and unavailability are inconclusive about
execution. Accepted content is read from authority even when the executor/journal
is offline. Evidence reads start no Coordinator or Worker. Agent consumption is a
separate `AgentRecords.consume_results/2` command with the accepted digest and
role-specific consumption kind; Runtime acceptance does not advance Agent state.
