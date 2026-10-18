# C independent check — event-reduced Agent

## Disposition and scope

Independent source review and in-scope fixes completed. **No known C defect remains
from this review.** This is not product acceptance: the broad integration run
still has exactly **26 D-owned legacy fork/history/export failures**. They were
executed, left visible, and neither rewritten, skipped nor compatibility-shimmed.

Loaded C's artifacts/check context/handoff, the accepted parent/main design and
A/B's contracts; traced reducer → loader/reference closure → context → atomic
prepare → actual prepared Runtime submission → accepted authority output → ordered
consumption → activation/continuation. Also reviewed memory behavior and the
Lifecycle/OperationOwner/Resources ownership paths. No nested agent, commit, push,
task-status/archive action, deployment or real-data migration/deletion was done.
Only C's spec was edited among the existing shared documentation. A/B's other
changes and the pre-existing design documents were preserved.

## Findings fixed

1. **Post-commit projection poisoning.** Durable could commit a repeated model
   preparation or an invalid consumption position, then have Reducer reject the
   returned events. Added preflight through the same pure reducer before policy
   writes. Reversed/duplicate consumption, illegal positions and repeated prepare
   now refuse with no version/history change. Actual committed events remain the
   only live projection input; synthetic preflight events are never persisted.
2. **Insufficient event decoding.** Control-shaped JSON alone did not establish a
   valid event. Added per-event payload keys, digest shape, envelope Operation
   linkage, first-event creation, pause/turn/step/ordinal and role-specific consume
   position checks. Continue must preserve its logical position and name exactly
   the pending identities. Unknown or malformed history is not skipped.
3. **Digest-valid malformed cache crash.** Cache reference traversal ran before
   validating the cache against history; a pending integer raised Access errors.
   Compare against the reduced supported prefix before dereferencing cache data.
   Missing/bad/version-incompatible caches still fall back, but bad history does
   not. Added a valid-cache/missing-history refusal regression.
4. **Cache reset the history budget.** Prefix and suffix each received a fresh
   100000-event/32 MiB budget. Carry actual counters across the boundary. A real
   36 MB event fixture (40 × 900000-byte control tags, cache after 35 tags) now
   refuses both cached and full loads; an earlier fixed high water still reads.
   The ordinary paging test also now has an actual nonempty checkpoint suffix.
5. **Incomplete immutable-request linkage.** A rewritten Operation description
   plus matching row digest could pass without matching its preparation event.
   Loader now checks the Operation-scope preparation digest and Agent-scope
   owner/turn/step/ordinal/prepared_seq linkage, as well as accepted digests,
   sources and local artifacts. Malformed source references fail safely.
6. **Malformed stored JSON raised a raw Ecto exception.** Reproduced strict
   Storage.JSON load failure during read-only reconstruction. Transaction.read
   narrowly maps Ecto.Repo.Queryable.struct_load!'s `cannot load … as type
   #Beamlet.Storage.JSON<…>` ArgumentError to invalid_data. Other ArgumentErrors
   still re-raise. No raw field contents escape through the API and no repair or
   successful fallback is fabricated. Verified on SQLite and PostgreSQL.
7. **Decisions could hide successful output.** A confirmed_failed decision could
   relabel an accepted successful model reply and bypass its text/Tool calls.
   Resolutions now require a named pending accepted uncertain/cancelled/deadline/
   unknown outcome; definite ok/error cannot be relabeled. Claimed-without-output
   remains undispatchable even with an explicit decision.
8. **Several uncertain siblings could never be continued.** Added one atomic
   `resolutions` list of named decisions; every uncertain sibling must be covered.
   A single incomplete decision commits nothing. Conversely, a safe input-only
   dependency interruption no longer requires fabricated execution evidence.
9. **Definite accepted model error looped forever.** Resume always expected an ok
   model value, so a real error repeatedly paused as unresolved. Consume definite
   model errors once to completed, publish an error view, and materialize a
   sourced failure notice rather than a successful assistant. Later input can
   proceed without reexecuting the failed model or inventing a resolution.
10. **Restored sibling dispatch continued after a blocker.** Changed the resume
    fold to stop on the first failure, leaving later attempts prepared. Pending
    lookup failures also return through the safe failure path instead of a match
    crash. The missing-first-profile test proves zero later Tool invocation and
    zero new owner helper.
11. **Old local senders were not explicitly fenced.** Registry inactivity did
    not prove that a blocked old OperationOwner had exited. Durable operations
    now register a transient Agent/generation identity with Resources; activation
    fences dead owners' inventoried groups and waits for observed DOWN. Delayed
    registrations for dead owners are refused. Fences have a 5s call budget and
    at most128 pending waiters; identity entries retire with their groups, with
    no unbounded persistent business/fence map. Both restore entry points reject
    a registered live identity. Live continue returns owners_retiring without a
    write until its existing groups retire. A suspended old controller is killed
    and its entire inventory observed DOWN before activation; actual native worker
    DOWN is additionally asserted, without claiming upstream/remote termination.
12. **Restore command replay was rejected.** The expected-version precheck
    rejected a repeat of an already committed activation. At the same activation
    head the identical Durable.restore command returns the same paused control,
    without another generation. Invalid expected-version types return invalid_data.
13. **Memory uncertainty could authorize more work.** Tool uncertainty was encoded
    as an ordinary observation, allowing another automatic model step; model
    uncertainty also permitted new input. Both now block subsequent execution/
    input in that memory instance. Tests use real waiting native model/Tool
    invocations and inject a valid Runtime terminal at the Server boundary, then
    assert actual worker DOWN and no next model call. Existing explicit memory
    stop/new-input and nested delegation semantics remain intact.
14. **Stored reply conversion silently dropped unknown fields.** Enforce exact
    neutral reply/call keys, and validate materialized model replies against the
    stored catalogue before constructing assistant history. Do not normalize an
    invalid accepted body into an apparently valid reply.
15. **Configuration version was a constant definition revision.** Caller now adds
    a SHA-256 configuration_version from the canonical effective nonsecret
    description, preserving model catalogue/config/placement or portable Tool
    profile/placement and excluding messages, arguments and credentials.
    ContextBuilder records definition_version separately. Actual prepared model
    and Tool descriptions carry the hash; parameter/schema/profile changes change
    it, while input/argument/secret changes do not. No credentials are persisted.
16. **Policy metadata could exceed the executable ceiling after its first check.**
    Recheck the complete model Operation after merging policy metadata, before
    atomic preparation. The exact-cap regression preserves the accepted original
    input but proves zero prepared Operations/steps on metadata overflow. No wire
    ceiling was widened.

The suspected partial-consumption assistant boundary was **not a reproduced bug**:
its new regression passed against the original implementation. It remains as
coverage for restoring only the remaining identities in original Tool order;
there was no speculative rewrite of that working path.

## Files changed by this check

- `apps/beamlet_agent/lib/beamlet/agent.ex` — accurate paused restore/decision docs.
- `apps/beamlet_agent/lib/beamlet/agent/{reducer,loader,context_builder,durable,server}.ex`.
- `apps/beamlet_agent/lib/beamlet/agent/integration/caller.ex`.
- `apps/beamlet_agent/lib/beamlet/agent/{lifecycle,operation_owner,resources}.ex`.
- `apps/beamlet_storage/lib/beamlet/storage/transaction.ex` — narrow corrupt-JSON read error.
- `apps/beamlet_agent/test/beamlet/durable_agent_test.exs` — 16 → 39 cases; existing
  assertions retained, including input/context bounds, accepted-only sources,
  replay equivalence and live ordered Tool execution.
- `.trellis/spec/backend/agent-durable.md` and this report.

## Exact final verification

All commands ran from the umbrella root with OTP29/Elixir1.20.4, seed631927.
PostgreSQL used the existing isolated local test cluster at
`/tmp/beamlet-storage-a-pg/socket:55481`; fixtures create/drop only their own fresh
throwaway databases. SQLite authority and executor-journal fixtures are real files.
The already-running cluster was not stopped or reinitialized. An unnecessary
pg_ctl start attempt was refused because it was already running; its separate log
is `/tmp/beamlet-storage-a-pg/c-independent-server.log`.

### Focused durable, both actual adapters

```sh
mix test apps/beamlet_agent/test/beamlet/durable_agent_test.exs --seed 631927
BEAMLET_AGENT_TEST_ADAPTER=postgres \
  BEAMLET_PG_SOCKET_DIR=/tmp/beamlet-storage-a-pg/socket BEAMLET_PG_PORT=55481 \
  mix test apps/beamlet_agent/test/beamlet/durable_agent_test.exs --seed 631927
```

- SQLite **39 passed**, 32.0s: `/tmp/beamlet-c-independent-sqlite-final6.log`.
- PostgreSQL **39 passed**, 35.0s: `/tmp/beamlet-c-independent-pg-final6.log`.

### Broad integration, with D failures deliberately visible

```sh
BEAMLET_PG_SOCKET_DIR=/tmp/beamlet-storage-a-pg/socket BEAMLET_PG_PORT=55481 \
  mix test apps/beamlet_storage/test apps/beamlet_runtime/test \
    apps/beamlet_agent/test apps/beamlet_harness/test apps/beamlet_node/test \
    --seed 631927
```

`/tmp/beamlet-c-independent-broad-final6.log`:

| App | Passed | Failed | Excluded |
| --- | ---: | ---: | ---: |
| Harness | 35 | 0 | 0 |
| Storage (real SQLite + PostgreSQL) | 74 | 0 | 0 |
| Runtime | 66 | 0 | 7 |
| Agent | 65 | 26 | 0 |
| Node | 68 | 0 | 20 |
| Total | **308** | **26** | **27** |

All26 failures are the15 old HistoryExportTest and11 old ForkTest cases, still
calling removed transcript/checkpoint APIs/old open shapes. This command is **not
a passing integration gate** and does not establish host/product acceptance.

### Clean ordinary Agent/lifecycle/Harness/Node gate

```sh
mix test apps/beamlet_agent/test/beamlet/agent_test.exs \
  apps/beamlet_agent/test/beamlet/agent/discovery_test.exs \
  apps/beamlet_agent/test/beamlet/agent/display_test.exs \
  apps/beamlet_agent/test/beamlet/agent/display_projection_test.exs \
  apps/beamlet_harness/test apps/beamlet_node/test --seed 631927
```

`/tmp/beamlet-c-independent-ordinary-final6.log`: Agent26 + Harness35 + Node68 =
**129 passed**,20 distributed excluded. Existing suspended-infrastructure helper
DOWN, nested delegation, terminal/ack, stop/stale callback, concurrent Agent/Tool,
provider/credential and role regressions were not weakened.

### Actual named peers

```sh
elixir --sname beamlet_c_independent_final6 --cookie beamlet_c_independent_final6_cookie \
  --erl '+S 2:2' -S mix test apps/beamlet_agent/test apps/beamlet_node/test \
  --only distributed --seed 631927
```

`/tmp/beamlet-c-independent-named-final6.log`: Node **20 passed**,68 ordinary
excluded,62.1s; actual peer VMs. Agent has no distributed-tagged cases (**0 executed,
91 excluded**); its authority/lifecycle paths are exercised via the named Node
suite. Same-host evidence only. OTP global overlapping-partition warnings remain
in the logs; no final named failure occurred.

### Static gates

All exit0:

- `mix compile --warnings-as-errors`: `/tmp/beamlet-c-independent-compile-final6.log`.
- `mix format --check-formatted`: `/tmp/beamlet-c-independent-format-final6.log`.
- `mix credo --strict --all`: `/tmp/beamlet-c-independent-credo-final6.log`,202 files,
  2440 mods/functions, no findings.
- `git diff HEAD --check`: `/tmp/beamlet-c-independent-diff-final6.log`.

No lint suppression, timeout/wire-cap enlargement, assertion deletion, automatic
write retry, business replay, provider call during replay/inspect, compatibility
fallback or unsafe real-dataset operation was introduced.

## Earlier failures and evidence limits

- `/tmp/beamlet-c-independent-red.log`: original five concrete regressions failed
  (17/22 passed): invalid prepare/consume committed, success-hiding decision,
  restore replay rejection, malformed-cache crash. Preserved, not overwritten.
- `/tmp/beamlet-c-independent-json-red.log`:35/36 passed; malformed stored JSON
  raised Ecto's ArgumentError before the narrow read normalization.
- First broad run exposed an over-broad new memory explicit-stop blocker (Agent
  display/new-input and Node nested-delegation failures). Removed that blocker,
  preserving the old scenarios while retaining uncertain-Result blockers. Final
  ordinary and broad C paths pass; no old scenario assertion was edited.
- First fence probe incorrectly assumed the native Runtime worker belonged to
  Resources inventory. Corrected the ownership assertion to controller/submit
  worker, retained a separate actual native-worker DOWN assertion, and verified
  every inventoried member dead before activation. The original failed lifecycle
  log is `/tmp/beamlet-c-independent-lifecycle-first.log`.
- `/tmp/beamlet-c-independent-named-first.log`:19/20 passed; the observation
  disconnect test observed an empty remaining node set. Concurrent broad/named
  runs and global partition warnings were present, but they do **not** establish
  the historical root cause. No Node/observation assertions, deadlines or retries
  were changed. Subsequent standalone named runs final/final2/final4/final5/final6
  each passed20. Retain this intermittent distributed observation risk for D.
- Earlier strict Credo findings were resolved with aliases/small helpers only;
  separate failed and final logs remain. A zero/empty editor cache was not counted
  as verification.

The byte-budget test crosses32 MiB with real stored events; the100000-event count
ceiling was source-reviewed, not exhausted by100001 database writes. These are
transaction/process-window and same-host peer tests, not physical-host, power-cut,
paid/live-model or external-side-effect exactly-once evidence. Full umbrella,
Dialyzer, Sobelow, catalogue drift, backend/release/e2e and host acceptance were not
run by this check and remain parent/D gates.

## D API and integration handoff

1. **No old transcript APIs.** Implement reference fork/inheritance and extend
   Reducer/Loader/ContextBuilder deliberately for cross-Agent direct immutable
   closure. Current C ownership/source checks are same-Agent; reserved fork/config
   mutation events are not a supported C policy. Do not recursively reconstruct a
   parent transcript or reown its Operations.
2. **Metadata changed intentionally.** ContextBuilder policy now uses
   definition_version (revision1), not the old constant configuration_version1.
   Caller.operation adds the content-derived configuration_version to every
   model/Tool Operation. Preserve it when merging policy and use
   Persistence.description on the final Operation verbatim. Durable.prepare's
   optional policy argument is still not a hidden metadata mutation API; direct
   callers must construct the complete Operation before preparing/submitting.
3. **Continuation decisions.** Keep singular named resolution support; multiple
   uncertain siblings use `%{"resolutions" => [named_decision, ...]}` atomically.
   Definite accepted errors need no fake resolution. Invalid/reversed/duplicate
   consumption must refuse before commit. A claimed unresolved attempt cannot be
   authorized by either decision form.
4. **Restore and local ownership.** Both restore paths reject live registered
   senders; activation waits for the old inventoried groups. OperationOwner passes
   private agent_identity to Lifecycle, removes it before Runtime.submit, and
   registers the six-element identity-bearing message (legacy internal five-element
   memory registrations remain accepted). Continue may return owners_retiring;
   that is not permission to submit work elsewhere. Restore command replay only
   returns the original activation while that activation is still the head.
5. **Read-only vs live APIs.** Durable.inspect needs no model/runtime/executor.
   Agent.restore constructs a live Server and still needs a valid binding; if
   startup configuration is absent, its durable activation remains paused. Adapt
   History/TraceExport/Verifier and the26 legacy tests to format2 facts, fixed high
   water, performed/inherited semantics, redaction/completeness and artifact closure.
6. **Dependency/version limits.** Fingerprints cover effective model parameters,
   catalogues and portable Tool profile/placement labels, not executor-local roots,
   mutable trusted registrations or adapter code. Matching/versioned trusted IDs
   and builds remain required. Existing prepared attempts retain their exact
   executor/boot identity: unavailable/mismatched dependencies must block, never
   reset or retarget a claimed/unknown attempt. No credential persistence or
   automatic rebinding/retry was added.
7. Adapt Server/Web/CLI/release/e2e durable callers and perform the remaining parent
   gates. Keep the known26 D failures and earlier intermittent named observation
   evidence visible until those integrations are actually accepted.
