# Runtime consumer handoff

Implementation handoff for child 1; this is not child acceptance or archival. Only Actions/Runtime and this child's execution/verification/handoff artifacts were changed by this worker. No Node, Agent, Harness, provider, Web, root dependency, task state, index or commit changes were made.

## Composition

`Beamlet.Runtime.child_spec(options)` delegates to `Beamlet.Runtime.SharedSupervisor`. Start once per VM. Default `execution: false` starts only the dedicated `Beamlet.Runtime.Groups` pg scope, Directory, temporary Coordinator DynamicSupervisor and NodeEndpoint. No Gateway or Task.Supervisor runs. All endpoints join the common `:nodes` group; shared-only reports advertise `execution_ready: false`, empty capabilities and no handlers.

Explicit `execution: true` adds `Beamlet.Runtime.ExecutionSupervisor`, whose Task.Supervisor (`Beamlet.Runtime.Workers`) and ExecutorGateway restart together with `:one_for_all`. Shared infrastructure also uses `:one_for_all`: loss invalidates references and never reconstructs submissions. Gateway loss kills its workers before capacity is re-advertised; Endpoint observes gateway loss, invalidates discovery, and restarts shared infrastructure. Endpoint incarnation changes invalidate previous membership/reports. A provider DOWN marks the executor unready, withdraws capabilities/environments and kills all its active workers conservatively. Provider recovery requires explicit subtree restart.

Node may instead start `{SharedSupervisor, shared_options}` and then `{ExecutionSupervisor, {executor_options, Beamlet.Runtime.Limits.new(shared_options)}}` as separate children. The explicit execution subtree announces itself to the existing Endpoint; absence of a gateway is safe. Supervision shutdown should stop execution before shared. Parent confirmed this composition interpretation during implementation. Node remains unmodified.

Executor options:

```elixir
[
  execution: true,
  handlers: %{"example.echo" => {MyLocalHandler, local_settings}},
  capabilities: ["opaque-capability"],
  environments: ["opaque-environment"],
  pools: %{"requests" => 2},
  providers: [provider_pid],
  limits: [refresh_ms: 1_000, expiry_ms: 5_000]
]
```

Handlers/settings and provider PIDs stay executor-local. Handler registration uses configured modules; operation payload never selects executable modules/functions. Runtime depends only on Actions and OTP applications, including `:crypto` for opaque IDs. No application callback activates runtime automatically.

## Public data

`Beamlet.Actions.Operation.new(keyword_or_map)` returns `{:ok, operation}` or `{:error, :invalid_operation}`. `Operation.validate(term)` returns `:ok` or that error. Fields/defaults:

- `kind`: nonempty binary, maximum 128 bytes; `version: 1`.
- `payload: %{}`; `metadata: %{}`; `capabilities: []` (at most 32); `environment: nil`.
- `allowed_nodes: nil` or at most 64 existing node atoms; no atomization of model input.
- `claims: %{}`: at most 32 binary pool names mapped to positive integer concurrent units.
- `budget_ms: 60_000`, integer 1..3_600_000.

Full serialized description is at most 256 KiB. Allowed nested values are atoms/numbers/UTF-8 binaries/proper lists/plain maps, maximum nesting depth 24. Tuples, structs, references, PIDs, ports, functions, invalid UTF-8 are rejected. Ordinary UTF-8 text, including slash-prefixed text, is data; absolute workspace roots must remain executor-local and conventional secret/root map keys are rejected recursively. This validates structure, not arbitrary text for the semantic presence of a secret; producers must never insert credentials. Input is never truncated.

`OperationRef`: `id` (opaque random binary), `pid` (ephemeral coordinator). `Execution`: `operation_id`, `attempt_id` allocated before dispatch, `endpoint`, executor `incarnation`, `handle: nil` until admission, and `state` (`:awaiting_admission`, `:running`, `:completed`, `:uncertain`). No eligible target leaves Execution nil. `ExecutionHandle`: admitted `id`, `gateway` PID, `incarnation`; addresses/references belong only to live runtime contracts.

`Result`: `operation_id`, optional admitted `execution_id`, `status`, `reason`, `value`, `source`, `metadata`. Statuses are `:ok`, `:error`, `:cancelled`, `:deadline`, `:uncertain`; sources are `:execution` or `:coordinator`. Result and terminal notification are limited to 1 MiB. Invalid/oversize handler output becomes `:invalid_or_oversize_result`; malformed return shape becomes `:invalid_handler_result`. Accepted Result metadata includes `attempt_id` (nil without an attempt), `sink_progress_dropped`, and on normal wrapper returns `producer_progress_dropped` and `gateway_progress_dropped`. Result validation requires bounded nonempty binary IDs, an execution ID for execution-origin Results, and plain-map metadata. Coordinators accept only matching gateway/incarnation/handle and execution-origin completion messages. Late terminal messages cannot overwrite the accepted value.

`Beamlet.Actions.Handler.run(payload, context)` returns `{:ok, bounded_data}` or `{:error, safe_data_reason}`. Context: `settings` from executor registration, `remaining_ms`, `progress` callback (`:ok` or `{:error, :progress_limit}`), and `cancelled?` callback. Cancellation sets an executor-local token before sending shutdown; a handler trapping exits can inspect it. Handler runs as a temporary MFA Task.Supervisor task. Handlers own cleanup of external resources; worker death does not prove remote effects stopped.

## Facade/events

`Runtime.submit(operation, owner: owner_pid, sink: sink_pid)` defaults both PIDs to caller and installs them before dispatch. Returns `{:ok, OperationRef}` or immediate `{:error, :invalid_operation | :capacity | :unavailable}`. `Runtime.status(ref)` returns `{:ok, %{execution: ..., result: ..., stopping: ..., progress_dropped: boolean}}` or `{:error, :unavailable}`. `Runtime.cancel(ref)` returns `:ok` while live and requests best-effort shutdown. Calling cancel after acceptance returns `{:error, :unavailable}`; status still exposes the retained result. `Runtime.ack(ref, sequence)` returns credit for a delivered progress event; it does not replay dropped events.

Sink messages, all correlated by the live ref:

```elixir
{:beamlet_operation, ref, {:progress, attempt_id, sequence, value}}
{:beamlet_operation, ref, {:result, %Beamlet.Actions.Result{}}}
```

The sink should acknowledge each consumed progress sequence. Progress is optional: maximum 256 attempted emissions, 20 per second window, 16 producer messages in flight, 16 unacknowledged sink events, 8 KiB full notification. Auxiliary callbacks use a linked, monitored wrapper-owned marshaler that forwards while the synchronous handler is running. The wrapper flushes its marshaler before returning; worker/gateway loss ends the marshaler. Callback users must stop their own producer children/resources; the generic runtime owns the wrapper and its marshaler. Terminal output is independent of sink credits. Dropped progress is indicated in the terminal metadata/status snapshot.

## Placement/lifecycle

Directory monitors common pg membership and endpoint PIDs, queries joins immediately, invalidates leave/DOWN reports, and refreshes nonce-correlated reports every second. It expires snapshots by local receive time after five seconds and bounds the union of snapshots/pending queries to 256 endpoints. `Directory.snapshots/0` exposes fresh `{endpoint_pid => report}` maps for Node composition; shared-only endpoints remain discoverable. Reports contain node, gateway PID, incarnation, readiness, opaque capabilities/environments, handler-kind booleans, available pools, utilization and executor-local lease. Typed report validation rejects unknown keys and malformed/oversize envelopes before caching. Registration limits: 32 handlers, pools, capabilities, environments and provider PIDs each; UTF-8 labels 1..128 bytes; positive pool units at most 3,600,000; each handler's local settings at most 64 KiB serialized. Modules must export run/2. Configuration reserves 512 bytes of report overhead against report_bytes before startup. No local settings/providers/credentials are published.

Selection filters protocol/kind, readiness, freshness, capabilities, environment, allowed nodes and all resource claims. Lower aggregate pool utilization wins, then stable node/incarnation ordering. Reports reserve nothing: gateway serially validates and charges all pools before starting a worker. A gateway-issued monotonic report lease is returned unchanged to that same gateway; no machine compares its clock to another machine's. Admission rejects expired leases and conservatively subtracts gateway-local report-lease age from the submitted remaining duration. This accounts for transport/queue delay without cross-node clock comparison; an old report can shorten the executor budget by its age. Refresh promptly for short operations. Attempt tombstones outlive the lease plus admission observation interval, preventing old legitimate dispatch envelopes from becoming fresh after tombstone expiry. No fallback, queue, retry, re-placement or replay exists.

Definite rejection: `:ineligible`, `:capacity`; coordinator no-target: `:no_target`. Admission observation timeout: `:uncertain/:admission_timeout`; connection loss: `:uncertain/:connection_lost`; owner/endpoint loss: `:uncertain/:infrastructure_lost`; deadline: `:deadline/:termination_unconfirmed`; unobserved cancellation: `:uncertain/:cancel_unconfirmed`. Cancellation confirmed by worker DOWN becomes `:cancelled/:worker_stopped`. Accepted racing success stays successful. An unrelated crash remains `:error/:worker_lost` even after a cancellation request. Observed shutdown or gateway-issued kill escalation can confirm `:worker_stopped`. Repeated cancel requests schedule one escalation per worker/coordinator. Infrastructure restart may invalidate a ref before a final notification; consumers must monitor refs and handle unavailable status.

Configurable positive bounded `limits` keys/defaults: `coordinators: 256` (includes retained), `retention_ms: 30_000`, `refresh_ms: 1_000`, `expiry_ms: 5_000`, `admission_ms: 2_000`, `cancel_ms: 100`, `attempts: 512` (active plus tombstones), `progress_count: 256`, `progress_credit: 16`, `progress_rate: 20`. Unknown/zero/negative/noninteger limits fail startup. Deployment byte limits are `operation_bytes: 262_144`, `result_bytes: 1_048_576`, `progress_bytes: 8192`, `report_bytes: 65_536`; each accepts 1024 through its default protocol ceiling. Operation bytes count the entire serialized description; Result/progress/report checks count their full transport notifications and sink envelopes where applicable. Overrides reject oversized input explicitly and normalize oversized output; they never truncate executable data. Nesting depth, directory endpoint count and maximum operation budget remain protocol ceilings. Other positive limits are bounded at 3,600,000.

## Review boundaries

Named-VM tests use real same-host peer VMs with stdio control, isolated peer names/test cookie, two schedulers, bounded boot/shutdown, explicit barriers and remote liveness/accounting inspection. This is not physical multi-machine acceptance. See verification.md for exact commands/counts, earlier repaired failures, tooling limits, and remaining review gaps.
