# A implementation handoff: authority format 2

## Scope and delivery state

Implemented on `refactor/durable-rebuild`, confined to `apps/beamlet_storage` and
this task's research evidence. No Runtime/Agent source edits, commits, pushes,
merges, task-status changes, real dataset deletion or production migration.
Pre-existing shared specs/design documents remain untouched by this worker.

The authoritative API inventory and parameter schemas are in
`apps/beamlet_storage/README.md`. This file highlights integration requirements;
**A passing Storage suite is not full umbrella/release acceptance**. The old
Agent adapters still call removed APIs. No independent checker was spawned
(recursion guard); the implementer applied the trellis-check checklist locally.

## Data layout

- Deleted authority v1 migration. New authority installation runs migration **2**,
  metadata `format_version = 2`; unchanged journal runs migration/format **1**.
- `Dataset.open` never initializes/migrates/repairs. SQLite performs read-only
  metadata/migration preflight before starting the configured writable Repo,
  then the ordinary verification runs again after startup. Identity, role,
  format, backup and migration guards remain fail-closed. PostgreSQL still
  opens only a provisioned dataset and checks metadata before admitting writes.
- Checkpoints add `through_seq`, `reducer_version`; digest covers projection JSON.
  They are optional, contain control/reference data and cannot own messages or
  request/reply bodies. Writing a checkpoint increments lock_version but allocates
  no Agent event. It currently requires the **current** through_seq.
- Operations add `step_id`, `role`, `owner_generation`, immutable Agent
  `prepared_seq`, and `sources`. `description` contains the complete fixed
  logical request. `description_digest` covers description; source/owner/step
  changes also conflict through whole-command hashing (or exact independent
  Operation replay comparison). `accepted_result` remains readable inline from
  authority storage; referenced artifacts are verified locally.
- Agent and Operation IDs use separate event scopes. Agent history never reserves
  an acceptance slot. Operation preparation writes own-scope seq 1; acceptance
  writes own-scope seq 2 and never CASes Agent version.
- No transcript-copy fork implementation or fallback survives. The reference fork
  API belongs to D and must be implemented before the product is integrated.

## B/C call contract

Boundary arguments are atom-key maps; all persisted JSON is string-keyed.
UUIDs remain canonical UUID strings. `step_id` and `tool_call_id` are strings up
to 255 bytes. Do not pass old `command: %{params: ...}`, `event`, `checkpoint`,
`agent: %{expected_version: ...}`, or `accept_seq` inputs: they are rejected.

Agent `position` is `%{agent_id: id, lock_version: n, generation: g}`. All Agent
commands have an explicit `command_id` UUID; Storage hashes **the entire actual
argument**, including position and requested data, instead of trusting a supplied
params map. Same command+same complete arguments returns the original response,
even if the Agent has moved. Same command+changed arguments conflicts. A fresh
command must use the current returned position. Command replay performs no new
write and does not grant dispatch permission.

### Creation/input

```elixir
AgentRecords.create_agent(repo, %{
  command_id: uuid, id: agent_id, authority_id: dataset_id,
  definition: definition_json # optional alias: string
})
# => {:ok, %{"agent_id", "generation" => 0, "lock_version" => 0,
#            "through_seq" => 1, "history_seq" => 1, "events" => [...]}}

AgentRecords.accept_input(repo, %{
  command_id: uuid, position: position, turn_id: turn_id,
  input: %{"text" => original_text}
})
```

The original input belongs to the `input.accepted` payload, not the prepared
model request. Event identity is the stable input reference. Version/seq advance
once. No checkpoint is necessary. `definition` is held by the Agent row;
`agent.created` carries `definition_version: 1` only.

### Preparation

```elixir
AgentRecords.prepare_operations(repo, %{
  command_id: uuid, position: position, turn_id: turn_id,
  orchestration: %{"mode" => "all"},
  operations: [
    %{
      operation: %{
        id: operation_id, owner_agent_id: agent_id, turn_id: turn_id,
        step_id: "step-1", role: "model", ordinal: 0,
        # tool_call_id: provider_call_id for tools
        description: %{
          "kind" => "model_call", "protocol_version" => 1,
          "payload" => complete_logical_request
          # optional refs/budget/claims/safety JSON
        },
        sources: ordered_sources
      },
      attempt: %{
        attempt_id: attempt_id, executor_id: executor_id,
        executor_boot_id: boot_id, budget: budget_json
      }
    }
  ]
})
```

1–8 members, unique IDs/ordinals, one prepared attempt each, active input turn and
same owner. Role is `model`, `tool`, or `summary`. Storage assigns preparation
generation and an individual Agent preparation position. The whole batch,
attempts, Agent events, CAS and command response commit together. Preparation
events contain Operation/step/ordinal/join references only. The returned
`operations` have operation_id, description_digest, attempt_id,
attempt_version=0, lock_version=0 and dispatch_state=prepared.

B must claim **these same committed attempts**, then perform the single admit
outside any storage transaction. It must not create another unrelated Operation
via old submit preparation. `OperationRecords.prepare/2` now accepts only an
independent, ownerless Operation + mandatory attempt, and supports exact replay.

Sources are an ordered JSON list of at most 128 entries:

```elixir
%{"type" => "input", "event_id" => event_id, "seq" => input_seq,
  "digest" => Codec.digest(input_event_payload, :event) |> elem(1)}
%{"type" => "accepted_result", "reference" => accepted_ref}
```

Input sources must match the same Agent event/digest and committed cutoff.
Accepted sources must match the same Agent accepted Result **and a previously
committed consumption**. Merely available evidence or an accepted-but-unconsumed
output cannot enter a new request. Policy/version/high-water/transformation
metadata can be fixed in description `refs`; Agent preparation events do not copy
source manifests. Source list shape is intentionally concrete, not an arbitrary
unverified JSON reference graph. D must extend validation for inherited references
when adding fork; no old copied-message fallback exists.

### Acceptance/consumption

`claim_dispatch(repo, %{operation_id, attempt_id, expected_version})` remains
prepared→send_claimed CAS once. It also refuses an unclaimed attempt prepared by
an older Agent generation. A claim is not replayable permission to dispatch twice.

`record_evidence(repo, %{id, operation_id, attempt_id, executor_id, evidence_id,
content, resolution?: json})` verifies receipt binding and returns the stored row
as JSON. Duplicate receipt content/identity/resolution must match. Late evidence
is still allowed after Agent generation changes.

```elixir
OperationRecords.accept_result(repo, %{
  operation_id: operation_id, expected_version: 0, result: full_result_json,
  evidence_id: optional_authority_evidence_row_id,
  artifact_ids: optional_uuid_list
})
# => accepted_result, accepted_digest, accepted_evidence_id,
#    operation_id, Operation history_seq and lock_version

accepted_ref = %{
  "operation_id" => operation_id, "accepted_digest" => digest,
  "consumption_kind" => "model_result" # tool_result / evidence_resolution
}
AgentRecords.consume_results(repo, %{
  command_id: uuid, position: position, turn_id: turn_id,
  accepted_refs: [accepted_ref], join: %{}
})
```

Acceptance has **no Agent argument/version**. It may persist a true late outcome;
it does not advance an old/new Agent turn. Consume checks owner, active turn,
preparation generation, digest and role; dedupe is Agent+Operation+kind. It stores
only references+join. Caller order is explicit consumption order, so C must supply
the desired ordinal/join order. A fresh partially/fully overlapping consumption
command conflicts; retry the original command to get its original response.
No accepted Result is overwritten. Cross-Operation evidence IDs and missing or
corrupt artifact references refuse acceptance transactionally.

### Control/cache/read boundaries

- `advance(repo, %{command_id, position, turn_id, type, payload})`: allowed types
  turn.interrupted / agent.continue_decided / agent.config_changed /
  context.selected; control JSON only. Higher-level decision semantics remain C's.
- `restore(repo, %{command_id, position})`: increment generation/version, clear
  cache pointer, append agent.activated with interrupted continuation; no dispatch.
  It does not fabricate a failed Result or rewrite old events.
- `checkpoint(repo, %{command_id, position, id, through_seq, reducer_version,
  projection, continuation, safe_to_fork})`: optional reference/control projection.
  Explicit Operation references must belong to the Agent and accepted digests must
  match. `Events.control/1` requires a JSON map and rejects body-bearing keys
  recursively. This is a structural contract, not a text/secret scanner.
- `AgentRecords.fetch/2` returns Agent identity/state independently of cache
  validity; `head_checkpoint` is nil in this facade. C loads an optional cache
  through `History.checkpoint_at(repo, agent_id, through_seq)`.
- `History.checkpoint_at` selects by explicit through_seq and returns
  `%{"checkpoint" => nil}` for missing/bad JSON/digest; full history is untouched.
  A new C reducer must still check supported reducer version and validate
  reference closure. `checkpoint_page` is a raw audit view, not cache recovery.
- `AgentRecords.command_response(repo, agent_id, command_id)` reads the exact
  original committed response after an unknown write outcome. Absent identity is
  conflict; absence alone is not proof external work never executed.
- `History.event_page` / `AgentRecords.history_page`: existing bounded keyset
  filters; use fixed `through_seq`. `History.operations` retains the old
  `after_history_seq` option name but orders/cursors by immutable **prepared_seq**,
  not mutable Operation history_seq. Acceptance cannot reorder requests.

## Event vocabulary/version

Central owner: `Beamlet.Storage.Events`, version 1. Generated Agent shapes:

| Type | Payload |
| --- | --- |
| agent.created | definition_version=1 |
| input.accepted | text (original input) |
| model.request_prepared | operation_id, step_id, ordinal, join |
| tool.batch_prepared | operation_id, step_id, ordinal, join (one/member) |
| operation.result_consumed | operation_id, accepted_digest, consumption_kind, join |
| agent.activated | generation, continuation=interrupted |
| turn.interrupted / agent.continue_decided / agent.config_changed / context.selected | caller control map |

Operation scope: operation.prepared(description_digest),
operation.result_accepted(accepted_digest). No body-bearing acceptance event is
needed because the Operation owns accepted_result. Common event fields retain id,
scope_id, seq, schema_version, turn_id, operation_id, causation/dedupe/provenance
and recorded_at. A consumption has dedupe_key consume:<operation_id>:<kind>.
Events also reserves agent.forked/context.inherited for D. There is no separately
persisted model.reply_observed body; C uses operation.result_consumed for both
model and tool observation.

## Preserved storage/safety constraints

- No automatic retry, wire-envelope enlargement, timeout enlargement, lint
  suppression, Handler/network/filesystem business effect or failure downgrade.
- Transaction/connection, Codec/JSON, Artifacts, ExecutorJournal and
  TerminalArtifacts implementations retain their budgets and unknown semantics.
- Codec caps are actual current source values: Operation/command 1 MiB,
  event/checkpoint/Result 4 MiB, depth32/node100000. Earlier planning referred to
  smaller **wire** caps; B must retain Actions/Runtime wire caps independently.
  Command hashing also bounds one preparation command to the command JSON cap.
- References verifies nested artifact_id/artifact_ids/artifact_refs in Agent
  definitions, prepared descriptions, accepted Results and control checkpoints,
  plus explicit acceptance IDs. Authority content remains locally readable.
- Journal format and APIs unchanged; all five journal scenario tests were
  retained in rewritten form: insert-once/restart unknown, first stop, terminal
  receipt/ACK, malformed attachments/transaction budget, raw/encoded attachment
  limits. Codec, lock-wait, identity/admission and load-side-effect tests remain.

## Validation evidence

Executed with real SQLite 3.53.4 and PostgreSQL 18.6, temporary cluster only:

```sh
BEAMLET_PG_SOCKET_DIR=/tmp/beamlet-storage-a-pg/socket BEAMLET_PG_PORT=55481 \
  mix test apps/beamlet_storage/test --seed 631927
mix format --check-formatted
mix credo --strict --all
git diff --check
mix compile --warnings-as-errors
```

Final gates after the command-response/read-doc and validation additions:
**64 tests passed** at seed631927, no exclusions; strict Credo checked 199 files
with no findings (2442 modules/functions); umbrella format and diff whitespace
checks passed. Logs are `/tmp/beamlet-storage-final-tests.log`,
`/tmp/beamlet-storage-final-credo.log` and
`/tmp/beamlet-storage-final-compile.log`. The temporary PostgreSQL cluster was
stopped after verification; its isolated files remain under
`/tmp/beamlet-storage-a-pg` and can be restarted explicitly if needed. The shared
suite runs
both adapters (14 cases/SQLite +15/PostgreSQL, plus other Storage cases); counts
are actual execution, not skips. Fixture driver-failure tests intentionally log
PostgreSQL backend termination and SQLite lock failure. Mix additionally warns
about test/support/contract_fixture.ex matching neither test filter; this is a
pre-existing loader-layout warning, not a passing adapter skip.

Root warning-fatal compile **fails** at the agreed intermediate integration
boundary, with three old Agent calls in
apps/beamlet_agent/lib/beamlet/agent/durable.ex:

- line289 OperationRecords.prepare_batch/2 removed; C must use atomic Agent prep.
- line336 AgentRecords.consume_result/2 removed; C must use digest references.
- line634 AgentRecords.fork/2 removed; D implements reference inheritance.

Storage itself compiles during the focused test gate. No full umbrella tests,
Dialyzer, named peer tests, release/e2e, physical-host or power-loss acceptance was
claimed. Those remain parent/B/C/D gates.

Earlier failures were fixed, not counted as passing: initial v1 expectations,
missing PG environment, one wrong cross-scope event count, initial strict Credo
findings, and the closed-file byte comparison before consistent WAL baseline.
The file-integrity test checkpoints its own fixture before capturing bytes;
read-only preflight then safely rejects v1 and byte equality passes. An earlier
statement that writable open alone caused the observed changed bytes was too
strong: preceding writer shutdown/WAL cleanup also raced the original baseline.
The read-only preflight prevents writable connection initialization regardless.

## Parent/spec synchronization

Do not overwrite the user's pre-existing shared spec edits. At integration, update
backend/database-guidelines and index to say: authority format2, journal1,
Agent-owned original inputs/ref events, Operation-owned fixed request/output,
no accept_seq, optional through_seq/reducer checkpoints and read-only preflight.
Replace the old API descriptions with the storage README contract. Continue to
mark complete Agent reducer/fork/export behavior as pending until C/D pass.

No known failing Storage gate remains after the recorded completed checks.
Higher-level live flow is deliberately not runnable until adapters are rewritten.
Do not restore deprecated APIs to hide that integration work.
