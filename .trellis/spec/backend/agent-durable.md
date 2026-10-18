# Event-reduced Agent orchestration

## 1. Scope / Trigger

Use for format3 Agent persistence, input, preparation, consumption, inspect and
paused continuation. Agent Storage owns records, events, commands, sources and
associations; Actions Storage owns neutral execution facts. Sources include
`apps/beamlet_agent/lib/beamlet/agent/{durable,reducer,loader,context_builder,server}.ex`
and `apps/beamlet_agent_storage/lib/beamlet/agent/storage/`. See
[State and Persistence](./database-guidelines.md) for profiles/installation and
[direct reference fork/history/export](./durable-references.md) for trace format2.
Independent final evidence is in the
[independent review](../../tasks/10-18-storage-action-decoupling/research/independent-review.md).

## 2. Signatures

```elixir
Reducer.new(agent_id)
Reducer.reduce(control, committed_event) # {:ok, control} | {:error, reason}
Loader.load(repo, agent_id, through_seq: seq, cache: false)
Durable.inspect(%{repo: repo, agent_id: id}) # read only, no model/runtime required
Durable.restore(locator, expected_version, command_id)
Durable.context(durable, catalogue)
Durable.prepare(durable, [%{operation: operation}], "model", sources)
Durable.consume(durable, operation_ids_in_ordinal_order, "completed")
Agent.restore(locator, expected_version, command_id) # paused live Ref
Agent.continue(ref, expected_version, decision, command_id)
# Pure APIs; normalized data only, no Repo/reader callback:
Core.Reducer.decode(event) # :ok | {:error, reason}
Core.Reducer.reduce(control, event) # {:ok, control} | {:error, reason}
Core.Reducer.replay(control, events) # {:ok, control} | {:error, reason}
Core.Context.start(control) # {:ok, accumulator} | {:error, reason}
Core.Context.append(accumulator, material) # {:ok, accumulator} | {:error, reason}
Core.Context.messages(accumulator) # {:ok, messages} only after all sources
Core.Context.finish(accumulator, catalogue) # {:ok, %{request:, sources:, policy:}}
Core.Context.build(control, catalogue, materials) # same result as finish
Core.Decision.reply_position(reply) # "completed" | "reply_recorded" | error
Core.Decision.resume(position) # :idle | :advance | :replay_reply | :pending | error
```

Durable.restore returns `{:ok, %{durable: d, alias: alias, control: control}}`;
Loader returns `{:ok, %{agent: row, control: control}}`. Position is
`%{agent_id: id, lock_version: version, generation: generation}`. Runtime wiring
is `%{authority_repo: repo, journal_repo: repo, executor_id: uuid,
executor_boot_id: uuid}`. Credentials remain transient in the live model binding.

## 3. Contracts

`AgentRecords.prepare_operations(repo, attrs)` requires exact atom keys `command_id`,
`position`, `turn_id`, `operations`, `orchestration`. Position is the Agent CAS
identity below; operations is1..8 `%{operation: attrs, attempt: attrs}` members.
Domain schemas/codecs validate the association fields and body-free control;
Actions validates its neutral portion again inside the participant.

Reducer version 1 consumes Agent Storage event schema version 1. State owns references,
turn/step/continuation/generation, pending ordinal/step identities, consumed refs,
resolutions and pause/block facts; it owns no request/reply bodies. Live Durable
projects only returned committed events. Unknown writes read command_response by
stable ID, never retry a write or business work. Durable preflights policy transitions
through that same reducer before writes: invalid prepare/consume/decision events
must not commit a history the live projection subsequently refuses. The decoder
checks payload keys, digest shape, envelope linkage, first creation event, step/
ordinal/turn identity, pause state and role-specific continuation/consumption.

Input is exactly `%{"text" => utf8}` at most 65536 bytes, checked before the
Agent Storage transaction and in replay. Preparation is the atomic `Beamlet.Agent.Storage.AgentRecords.prepare_operations/2` batch
API for both model and tool work. Only after commit may OperationOwner call public
Runtime.submit with `prepared: member`. Acceptance does not advance Agent seq.
Consumption reads full accepted Results from authority, then commits references
and join position. Tools join by original ordinal, independently of acceptance
order. Complete model replies and full sibling batches validate before dispatch.
The executable byte ceiling includes configuration and policy metadata; recheck
that full model Operation before preparation, not only the earlier bare request.

Agent Storage `Schema.Operation` is a read-only projection through its
`agent_operation_projections` SQL view, joining Agent `agent_operations` with
Actions `operations`. Owner/turn/step/role/ordinal/tool-call/generation/prepared_seq
and ordered sources belong to the association. No projection writes may substitute
for Actions APIs. Agent events are `agent_events`; preparation/acceptance facts
are separate `operation_events`. Agent Storage `History.operation_event/3` projects
an Actions event with scope_id for trace readers; it never merges the logs.

ContextBuilder ordinary policy 1 materializes original inputs and previously
consumed accepted Results in timeline order. Its policy metadata fixes policy/
instruction versions, Agent definition_version and through_seq. Caller adds a
content-derived configuration_version to every model/Tool Operation before byte
validation: SHA-256 of the canonical nonsecret execution description with request
messages/arguments removed (the model catalogue remains). Model parameters,
schemas and portable profile/placement changes therefore change that version;
conversation input and credential changes do not. This is distinct from definition
revision 1, not a constant configuration label. Sources belong to that Operation.
Opaque executor-local profile/environment IDs still require matching trusted
registrations/builds; the hash does not inspect executor roots or adapter code.
No unconsumed evidence/output enters context.
A prepared request is reused exactly; changed dependencies fail description equality.
Native context limits remain 128 messages / 1 MiB. Model steps remain 16, tools 8.

Loader fixes through_seq before 100-event keyset pages (100000 events / 32 MiB
maximum per history traversal); reference traversal has a 5s deadline. Cache
validation compares its projection to the supported history prefix, then reduces
the suffix, so it currently revalidates the prefix rather than avoiding its I/O.
Missing, corrupt, unsupported or semantically inconsistent caches fall back to full
history. Corrupt history/references block. Accepted bodies, including pending
unconsumed outputs, must match the Operation acceptance event digest; consumed
references additionally match that digest. Descriptions also match the immutable
Operation preparation event, and owner/turn/step/ordinal/prepared_seq match the
Agent preparation event. Cache content is compared to reduced history before any
cache-supplied reference is dereferenced; a digest-valid malformed cache must not
raise. Prefix and suffix share one history budget. No executor/provider is contacted.

Activation increments generation, appends agent.activated, and pauses without
dispatch. Both restore entry points reject an already registered sender before
writing. OperationOwner registrations carry transient Agent/generation identities;
Resources fences dead owners' inventoried groups and waits for observed DOWN
before activation (5s call, at most128 pending fences). Registrations delayed past
owner death cannot start workers. Runtime remains responsible for cancellation;
fencing local helpers is not proof of remote/upstream termination. An identical
Durable.restore command at the same activation head returns the same paused
control without another generation. Live continuation returns owners_retiring
without committing while the previous Server-owned groups remain inventoried.
Agent create/fork create an opaque dispatch scope in the same transaction. Restore
locks Agent then rotates scope as generation advances. Global lock order is
Agent -> scope -> Operation; Actions claim never reads/locks Agent. Preparation
uses Actions `prepare_in_transaction/2` on the SAME Repo, validates sources/control,
and writes neutral Operation/attempt/event, immutable Agent association, Agent events
and original command response in one outer commit. A failure in any batch member
rolls everything back; participant errors must propagate to outer rollback.

Explicit continuation adopts accepted output by updating association eligibility
only; it does not reauthorize accepted execution. Pending prepared work calls
Actions reauthorization at the new scope epoch in that same transaction. Claimed
unresolved attempts refuse. Fetch refreshed Operation lock_version and scope/epoch
after continuation for Runtime's exact prepared binding; command replay still
returns its original saved response. Ordered sources and logical description stay
fixed. Old prepared generations cannot claim. Late acceptance cannot itself advance Agent.
Uncertain/cancelled/deadline/unknown accepted results require an explicit decision
naming the pending operation and confirmed_failed/confirmed_executed; consumption
then uses evidence_resolution without changing the accepted Result. A decision
cannot relabel an accepted ok/error outcome or authorize a claimed unresolved
attempt. For several uncertain siblings supply all named resolutions atomically:
`%{"resolutions" => [%{"operation_id" => id, "resolution" => "confirmed_failed"}, ...]}`.
A safe input-only/dependency interruption needs no fabricated execution resolution.
Accepted definite model errors are consumed once to completed with an error view;
context carries a sourced failure notice, not a fabricated successful assistant.
Unknown fields in stored model replies/calls are refused, not normalized away.
Restored sibling dispatch stops at the first blocker; later siblings stay prepared.

Memory mode likewise blocks automatic follow-on work and new input after an
uncertain/cancelled/deadline model/Tool Result (create a fresh memory Agent rather
than claiming durable resolution). Its existing explicit stop/new-input and
nested-delegation lifecycle behavior is retained; this is not durable recovery.

## 4. Validation & Error Matrix

| Boundary | Result |
| --- | --- |
| Unknown event version / missing seq | schema_unsupported / invalid_history |
| Normalized payload exceeds root depth32 / malformed inherited shape | invalid_history in decode/reduce/replay |
| Missing, extra, reordered or substituted context material / incomplete accumulator | invalid_reference |
| Invalid historical model reply before a later missing source | invalid_reply; no read of later source |
| Invalid input shape, encoding, >64 KiB | invalid_data before commit |
| Malformed stored JSON refused by owning strict JSON type | invalid_data on read and write facade; rollback, no repair |
| Missing/invalid checkpoint | full-history fallback |
| Corrupt accepted/body/source digest | invalid_reference |
| History count/bytes/gap | history_limit_or_gap |
| Native context count/bytes | context_limit |
| Full executable envelope including policy exceeds captured cap | executable_input_limit, zero prepare |
| Claimed unresolved / unapproved uncertainty | unresolved_execution |
| Changed prepared request dependencies | dependency_missing |
| Prior local owner groups not retired | owners_retiring before decision/activation |
| Decision relabels definite accepted output | invalid_reference, no commit |
| Stale live continuation version | stale_version |
| Already registered restore identity | already_active, no generation change |

## 5. Good/Base/Bad Cases

Good: accept raw input, commit immutable model request, execute once, accept output,
consume its ref, atomically prepare validated tools, join ordinal refs.
Base: input-only history with no checkpoint/provider/executor remains inspectable
and may be activated paused. Bad: accept an oversized input and discover the limit
only after reducer failure; that leaves persisted and live positions inconsistent.

## 6. Tests Required

`durable_agent_test.exs` runs SQLite by default; set
`BEAMLET_AGENT_TEST_ADAPTER=postgres`, `BEAMLET_PG_SOCKET_DIR`, optional
`BEAMLET_PG_PORT/BEAMLET_PG_USER` for actual isolated PostgreSQL datasets. It shares
Agent Storage's throwaway database fixture and uses a real SQLite executor journal.
Assert zero model calls during inspect/replay, accepted resume without reexecution,
claimed refusal, consumed reply/tool resume, exact 64 KiB and native message/byte
limits, unconsumed-source exclusion, corrupt-acceptance refusal, multi-page replay,
cache fallback (including digest-valid malformed refs), checkpoint+nonempty suffix,
fixed older high water, and live/partial Tool consumption order. Exercise actual
32 MiB history overflow with a valid near-limit cache prefix plus nonempty suffix;
the cache must not reset the total budget. Include policy metadata at the exact
executable ceiling and require zero prepared Operations on overflow. Refuse invalid
prepare/consume before writes, missing history despite valid cache, forged request
replacement, success-hiding resolutions, and incomplete multi-Tool resolutions.
Cover definite model-error continuation, changed dependencies with zero sibling
dispatch, memory unknown model/Tool blockers, suspended old owner fencing and
actual inventoried group DOWN before activation. Malformed stored JSON must return
a safe error, not Ecto's raw field-bearing ArgumentError; normalize only the strict
owning JSON struct-load failure (see [Error Handling](./error-handling.md#scenario-strict-persisted-json-failure)) and re-raise unrelated programmer errors. Assert
effective configuration versions change for model/schema/profile changes but stay
stable across inputs/arguments/credentials, including metadata on actual prepared
model/Tool requests. Keep Agent/Node actual helper DOWN
regressions while infrastructure stays suspended and the named distributed suite.

Core regressions live in `apps/beamlet_agent_core/test/core_test.exs`; adapter
parity and read-order assertions live in Agent's `core_adapter_test.exs` and
`context_read_order_test.exs`. Run these with `mix test --no-start` as well as the
ordinary Agent suite. Assert payload root31/32 acceptance and root33 refusal
through decode/reduce/replay, independent of wrappers; description/result roots
have independent depth budgets. Exercise nonempty inherited input/result and
resolved-result manifests, missing/extra fields, UUID/digest/sequence errors and
resolution-kind mismatches. Assert context_limit at the overflowing prefix before
any missing/corrupt/valid suffix read, and invalid_reply before a missing suffix.
Exact JSON list byte tests include brackets, commas, escaping and multibyte UTF-8;
1 MiB accepts and one byte over refuses. Do not validate incomplete tool prefixes
as complete requests before all selected sources are converted.

## 7. Wrong vs Correct

Wrong: trust an accepted body merely because the reference has not been consumed,
or let a post-commit reducer discover an input limit.
Correct: verify the committed acceptance digest even for pending output, and reject
unsupported input at the write boundary. Checkpoints do not repair bad history.

Wrong: preload all context materials, then convert them, or count event/replay
wrappers against the payload depth limit. Correct: verify and append one source
before reading the next, and validate each domain value from its own depth root.
An overflow at a valid prefix must win over a missing later source.

## Agent Core boundary

`beamlet_agent_core` owns `Beamlet.Agent.Core.Reducer`, `Context` and `Decision`.
Core has no Agent/Runtime/Storage/Ecto dependency or external effects. The Agent
Reducer facade validates persisted envelopes with foundation Codec and Agent Storage Events and passes
the canonical input digest as transient normalized data; persisted state keys and
versions remain unchanged. Payload depth32 is measured from the payload root,
independently of event and replay containers. Inherited input/result entries have
exact normalized shapes and validated UUIDs/digests/sequences/resolutions.
An inherited input has exactly `type`, `artifact_id`, `digest`, `event_id`, `seq`
and `source_agent_id`. An inherited result has exactly `type`, `source_agent_id`,
`description_digest`, `reference` and `resolution`; its reference has exactly
`operation_id`, `accepted_digest` and `consumption_kind`. UUIDs are canonical
lowercase strings, digests are 64 lowercase hex characters, and sequences are
positive integers. Consumption kind is model_result/tool_result/evidence_resolution;
only evidence_resolution requires a nonnil resolution with exactly `resolution`,
`decision_event_id`, `seq` and a confirmed_failed/confirmed_executed value.
Materials bind `source` to the next selected timeline occurrence and carry either
`input` (exactly `%{"text" => utf8}`) or `operation` plus optional `resolution`.
ContextBuilder loads and verifies each ordered source-bound material, then calls
the pure incremental context accumulator before reading the next source. Conversion
and exact message/byte limits therefore preserve first-error and read-stop behavior;
current catalogue/request validation waits until the selected timeline completes.
Core checks ordered membership, completeness, operation identity and resolution
association; digest, ownership and
inherited closure verification remain in the loader. Historical model replies use
the stored catalogue. Explicit repeated selected timeline occurrences retain the
existing exact-limit behavior. Server and Durable call pure continuation/fork
decisions while retaining transactions, lifecycle and fixed request recovery.
