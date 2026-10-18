# C implementation handoff

## Delivery and boundaries

C's format-2 Agent adapter is implemented on the shared integration branch. No
commits, pushes, merges, task status/archive changes, deployment, real dataset
migration/deletion or sub-agent dispatch occurred. A/B changes and the pre-existing
parent design documents were preserved. D must complete reference fork/history/
export and host/product integration; this is not full product acceptance.

Owning C files:

- `apps/beamlet_agent/lib/beamlet/agent/{reducer,loader,context_builder}.ex` (new)
- `apps/beamlet_agent/lib/beamlet/agent/{durable,server}.ex`, facade `agent.ex`
- `apps/beamlet_agent/test/beamlet/durable_agent_test.exs`
- Necessary Storage continuation integration in `agent_records.ex`, safe error
  mapping in `transaction.ex`, and dual-adapter continuation tests in
  `storage_contract_test.exs` (shared files also contain A/B's earlier work).
- `.trellis/spec/backend/agent-durable.md` plus current-status pointers in index,
  Agent orchestration and database guidelines. Historical sections await D rewrite.

There is no compatibility implementation of old `Agent.fork/4` or transcript-copy
Storage API. Do not reintroduce one to pass the old tests.

## Exact APIs and structures

See `.trellis/spec/backend/agent-durable.md` and Storage/Runtime READMEs.

`Reducer.version/0 == 1`; `new(agent_id)`, `reduce(control, event)`,
`replay(control, events)` return `{:ok, control}` or a safe error. State has exactly
agent_id/through_seq/generation/resolutions/definition_version/turn_id/step/
continuation/inputs/pending/consumed/timeline/blocked/paused, all string keys.
Inputs and timeline are source references, not message bodies.

`Loader.load(repo, agent_id, opts \\ [])` returns
`{:ok, %{agent: persisted_row, control: reduced_state}}`. Options are `through_seq`
(default captured Agent history_seq) and `cache` (default true). `Loader.operation`
verifies owner, immutable description digest, artifacts, sources, and acceptance
body against Operation-scope seq2 acceptance event; consumed refs also verify their
digest. `Loader.references/2` validates pending and consumed closure.

`ContextBuilder.build(repo, control, catalogue)` returns
`{:ok, %{request: %{"messages" => messages, "catalogue" => catalogue},
sources: ordered_timeline, policy: policy_map}}`. `materialize/2` produces disposable
messages. Policy fields are policy_version=1, instruction_version=1,
configuration_version=control.definition_version, through_seq. Live model dispatch
merges this policy into Operation metadata before `Persistence.description/1`.
`reply/1` converts neutral stored replies; Harness validates the complete reply.
`observation/2` refuses unresolved uncertainty unless a recorded resolution exists.

`Durable.open(repo, %{agent_id:, authority_id:, definition:, command_id:, alias?:})`
returns a Durable struct after projecting committed creation events.
`with_runtime/2` accepts authority_repo/journal_repo/executor_id/executor_boot_id;
`position/1` returns `%{agent_id:, lock_version:, generation:}`.
`accept_input(d, %{text:, turn_id:, command_id:})` returns `{:ok, next}`.
`context(d, catalogue)` delegates to the ordinary policy.
`prepare(d, operations, role, sources, policy \\ %{})` returns
`{:ok, next, committed_members}`. Operations are `%{operation: actions_operation}`
for model and `%{id: tool_call_id, operation: actions_operation}` for tools.
It fixes step_id `step-N`, roles model/tool, ordinal by list order, owner/turn,
request description, sources and one attempt in the same Agent transaction.
The optional policy argument itself is unused; callers must fix policy metadata in
Actions.Operation as Server does. No hidden second preparation happens in Runtime.
`persistence(d, member)` returns the Runtime Persistence struct;
OperationOwner uses public Runtime.submit with `prepared: member` and live owner.

`consume(d, ordered_operation_ids, position)` reads accepted Results and writes
only refs with join.position. Model positions are completed/reply_recorded;
completed tool batch position is await_model_result. Kinds model_result/tool_result
or evidence_resolution are selected by Operation role and explicit resolution.
`block(d, reason)` appends turn.interrupted.
`decide(d, %{decision:, command_id:})` validates pending positions then appends
agent.continue_decided and returns the next Durable struct.
`inspect(locator, opts \\ [])` is Loader only, no model/runtime dependency.
`restore(locator, expected_version, command_id)` returns
`{:ok, %{durable: next, alias: alias, control: next.control}}`, paused.

Live APIs: `Agent.restore(locator, expected_version, command_id)` returns a paused
Ref; requires a valid live binding to construct Server, but read-only Durable.inspect
never requires it. Existing registered identity returns already_active before
activation. `Agent.continue(ref, expected_version, decisions, command_id)` returns a
current snapshot and schedules only a legal continuation. `Agent.input/3` retains
command identity for input replay and returns the original turn without dispatch.

## Events and control transitions

All Agent events schema_version1, contiguous committed seq, scope_id=Agent ID.
Storage owns the taxonomy and actual event allocation.

- agent.created: definition_version=1; initial await_input.
- input.accepted: exactly text; projection stores event_id/seq/payload digest and
  sets await_model_result. Storage rejects non-UTF8 or >65536 bytes before commit.
- model.request_prepared / tool.batch_prepared: operation_id/step_id/ordinal/join;
  one event per member. No source manifest or request body copied into Agent.
- operation.result_consumed: operation_id/accepted_digest/consumption_kind/join;
  first pending ordinal only, append source ref and advance join.position.
- agent.activated: incremented generation/continuation=interrupted; projection
  preserves the logical pending position but sets paused. No failed Result forged.
- turn.interrupted: safe reason/control only, paused+blocked.
- agent.continue_decided: position/resume_operations/decision; clears pause/block
  and records resolution identity when explicitly provided.
- context.selected: control event accepted as a no-op by policy1.

Generic taxonomy includes config/fork/inheritance events but C does not implement
an API for configuration mutation or fork reduction; D must add the inherited
control cases and reference closure. Unknown/unsupported events block, never skip.
Operation scope remains operation.prepared seq1 / operation.result_accepted seq2.

Continuation transaction adopts only named pending prepared/accepted Operations
into the new owner_generation. Claimed-without-accepted output refuses
unresolved_execution. This permits first dispatch of unclaimed prepared work and
consumption of previously accepted work without permitting another claimed admit.
Accepted uncertain/cancelled/deadline/unknown blocks by default. Explicit decision
must name the pending operation and use confirmed_failed/confirmed_executed;
accepted output is never overwritten. Decisions do not make a claimed unresolved
attempt dispatchable. The live facade rejects old incarnations/versions.

## Verification evidence

All commands from umbrella root, seed631927. PostgreSQL is the existing isolated
local PostgreSQL18 cluster at socket `/tmp/beamlet-storage-a-pg/socket`, port55481;
fixtures provision/drop only their own test databases. SQLite engine3.53.4.

Final broad run:

```sh
BEAMLET_PG_SOCKET_DIR=/tmp/beamlet-storage-a-pg/socket BEAMLET_PG_PORT=55481 \
 mix test apps/beamlet_storage/test apps/beamlet_runtime/test \
 apps/beamlet_agent/test apps/beamlet_harness/test apps/beamlet_node/test --seed 631927
```

`/tmp/beamlet-c-final-regression.log`: Harness35 passed; Storage74 passed (actual
SQLite+PG); Runtime66 passed/7 distributed excluded; Agent42 passed/26 failed;
Node68 passed/20 distributed excluded. Total285 passed,26 failed,27 excluded.
Every failure is in old D-owned `history_export_test.exs` (15) or `fork_test.exs`
(11), mostly setup calling old Durable.open shapes, with warnings for removed old
fork functions. They remain visible, unweakened and unskipped. This run is NOT a
passing full integration gate.

Focused final durable Agent suite: **16 SQLite passed**
(`/tmp/beamlet-c-final-sqlite-agent-3.log`), **16 PostgreSQL passed**
(`/tmp/beamlet-c-verified-pg-agent.log`). Repeat PG with:

```sh
BEAMLET_AGENT_TEST_ADAPTER=postgres \
 BEAMLET_PG_SOCKET_DIR=/tmp/beamlet-storage-a-pg/socket BEAMLET_PG_PORT=55481 \
 mix test apps/beamlet_agent/test/beamlet/durable_agent_test.exs --seed 631927
```

Actual named peers:

```sh
elixir --sname beamlet_c_check --cookie beamlet_c_check_cookie --erl '+S 2:2' \
 -S mix test apps/beamlet_agent/test apps/beamlet_node/test --only distributed --seed 631927
```

`/tmp/beamlet-c-final-named.log`: Node **20 passed/68 excluded**, actual peer VMs,
62.8s. Agent has no distributed-tagged tests (0 executed/63 excluded at that time);
Agent lifecycle/discovery/authority cases are exercised through Node's named suite.
Agent ordinary lifecycle tests execute in the broad run, preserving actual DOWN
assertions before suspended infrastructure resumes. OTP global disconnect warnings
are present; no failures. Same-host evidence only, no physical-host claim.

Final static checks all pass:

- `mix compile --warnings-as-errors`: `/tmp/beamlet-c-verified-compile.log`
- `mix format --check-formatted`: `/tmp/beamlet-c-verified-format.log`
- `mix credo --strict --all`: `/tmp/beamlet-c-verified-credo.log`, 202 files, no findings
- `git diff --check`: `/tmp/beamlet-c-verified-diff.log`

No Dialyzer/Sobelow/catalogue/release/full-umbrella/e2e/physical/power-loss
acceptance is claimed; these remain D/parent final gates. Incidental editor
probes are not a substitute for these checks.

Earlier failed logs are preserved: final-durable.log exposed the first incorrect
assumption that accepted_digest was a stored Operation column (it is in the
acceptance event); final-sqlite-agent-2.log and final-pg-agent-2.log exposed the
input commit-before-reduce limit defect; final-credo-2.log had test alias findings.
All were corrected without removing assertions, increasing limits/timeouts,
suppressing lint, retrying business work or adding compatibility APIs.

## AC evidence and practical limits

AC1: live/control vs full replay; checkpoint+suffix equality over121 events/two
pages; corrupt cache fallback; replay/inspect/restore zero model-call assertions.
Cache currently revalidates its entire prefix before trusting it, so it provides
no prefix-I/O speedup. Each history traversal is bounded at100000 events/32MiB;
reference traversal has a5s deadline. Unknown history is blocked, never truncated.

AC2: input-only restore; prepared original identity executes once; accepted model
resume has zero model calls; consumed model reply resumes tools; accepted tool
batch resumes in ordinal order without tool dispatch; duplicate input/consumption
refusal and both-adapter continuation adoption tests.

AC3: immutable complete request description/sources, version policy metadata,
accepted-but-unconsumed source rejection, corrupted acceptance refusal before
activation. Prepared dispatch reconstructs from stored description and compares
exactly, preventing changed binding/routes/catalogue from mutating old work.

AC4: read-only inspect works without model/runtime; unresolved claimed work blocks;
uncertain accepted output requires explicit operation decision and remains immutable;
old generation claims refuse in both adapter Storage contracts; normal Agent/Node
incarnation/helper ownership regressions retained.

AC5: exact65536/one-byte-over input with zero write on rejection, native context
128/129 message and byte-limit cases, multi-page/corrupt/missing cache,
helper lifecycle/concurrent native Tool and actual named peers covered. This is
process/transaction-window and replay evidence, not power-cut/physical-host proof.

## D requirements

1. Implement reference fork and agent.forked/context.inherited reducer/loader/context
   semantics with validated direct closure and explicit risk; no recursive parent
   transcript construction or Operation reownership. Current Loader validates same
   Agent ownership/sources only; extend deliberately for inherited sources.
2. Rewrite History/TraceExport/Verifier and the26 old tests to format2 refs. Preserve
   redaction/completeness/artifact/cursor/high-water guarantees and performed vs
   inherited distinction. Full tests still call removed APIs; do not shim them.
3. Adapt host/release/e2e/Web/CLI durable calls to new definitions/control API.
   Standalone ephemeral paths already pass ordinary Agent/Node checks; durable
   host/product tests have not been counted as passing here.
4. Handle bound durable configuration/version changes explicitly if adding mutation;
   policy1 currently uses definition_version1, with effective request configuration
   frozen in each Operation. No generic config mutation policy was added by C.
5. Run final parent gates including full umbrella, named distributed, real PG,
   release/e2e/backend compile and static analysis; update historical guide sections
   and product status only after those pass.
