# A independent check evidence

## Scope and result

Independent Check Agent review of the complete uncommitted Storage format-2 change,
against this child's PRD/design/implementation plan, curated check.jsonl context,
parent design, accepted agent-operation-persistence design and parent
research/implementation-authorization.md. No subagents, commits, archives,
Runtime/Agent edits, shared pre-existing design/spec edits or real-data operations.

No known failing Storage check or unresolved in-scope defect remains after the
fixes below. This is a Storage-stage result, not complete durable product acceptance.

## Findings fixed

1. **Terminal work could still acquire initial dispatch permission.** A prepared
   attempt remained claimable after its Operation already had an accepted Result,
   including uncertain. Claim now requires accepted_result to remain NULL. A
   shared SQLite/PostgreSQL regression accepts uncertain, replays the original
   preparation command, then proves claim refuses and attempt remains prepared.
   Replaying a preparation response does not grant fresh dispatch permission.
2. **PostgreSQL claim checked facts without holding them through commit.** Restore
   could change owner generation between its read and the attempt CAS. Claim now
   locks Operation FOR UPDATE and owned Agent FOR SHARE through transaction commit,
   serializing against acceptance and activation. SQLite retains immediate writes.
   The shared regression holds an actual outer transaction uncommitted after
   restore or acceptance, verifies claim waits, releases the writer, and verifies
   stale_generation or conflict respectively. No effect is sent in a transaction.
3. **Reference verification was missing from three control entries.** Preparation
   orchestration, consumption join and advance payload had body/JSON checks but
   could persist foreign Operation or missing artifact references. All now reuse
   the checkpoint's recursive owner/digest/artifact verifier inside the write
   transaction. Shared regressions reject foreign owners and missing artifacts at
   all three entries and verify no version or Operation was partially committed.
4. **Turn keyset paging filtered rows before grouping.** Interleaved facts could
   repeat an earlier turn or skip a later turn when cursor used last_seq. Filtering
   now uses HAVING min(seq) > after_first_seq; next cursor is first_seq. Regression
   covers interleaved turn events, complete min/max values and exhaustion.
5. **Independent preparation could bypass Agent orchestration validation.** The
   ownerless entry accepted model/tool roles and arbitrary unverified sources.
   It now requires empty sources and absent owner/turn/step/role/ordinal/call
   metadata. Shared tests reject ownerless model role, step and forged accepted
   source before creating an Operation. Generic independent Operations remain
   supported without Agent orchestration metadata.

Changed in this check: agent_records.ex, operation_records.ex, history.ex,
storage_contract_test.exs, Storage README, and this evidence file. Refactored new
helpers/test quote fragments to pass the existing strict Credo rules; no suppression,
timeout/cap enlargement, assertion removal or compatibility shim.

## Review coverage

- Original input is its own committed Agent event; owned preparation requires an
  active input turn. Complete immutable requests and ordered sources live on
  Operations, accepted bodies on authority Operations/artifacts. Agent preparation
  and consumption events contain references rather than request/reply bodies.
- Preparation commits all Operations/attempts, both scopes' events, Agent CAS and
  command response together. Duplicate attempt failure after the first insertion
  rolls back the batch. Injected second-consumption failure rolls back the first
  consumption and Agent CAS. Existing tests execute these on both real adapters.
- Agent sequences count committed events only; Operation acceptance has its own
  scope and does not mutate Agent version. Competing control CAS and concurrent
  acceptance preserve continuous committed sequence positions.
- Complete argument command digests detect changed requests; exact retries return
  original responses, including old positions. Dispatch requires a separate
  single-use claim. Accepted Results cannot be overwritten; receipt replay checks
  operation/attempt/executor/content/resolution identity. Late evidence remains
  allowed after generation changes without advancing Agent control state.
- Consumption checks owner, active turn, preparation generation, accepted digest,
  role and consumption dedupe. Request accepted-result sources require prior
  committed consumption. Original-input sources verify identity/seq/digest/cutoff.
- Checkpoints are optional and body-free, with explicit through_seq, reducer
  version and projection digest. Corrupt cache reads return nil without damaging
  raw event/body reads. Unknown reducer semantics/reference closure still belong
  to the C loader, rather than being inferred by Storage.
- Authority metadata/migration is exactly 2, journal remains 1. SQLite open runs
  read-only preflight before a writable Repo. The legacy-format regression changes
  isolated fixture metadata/migration to 1 and checks unchanged closed-file bytes;
  it does not operate on a user's old database. No migration/repair fallback exists.
- Journal/Codec/Artifacts/Transaction implementations retain their existing
  limits, first-stop provenance, restart unknown, attachment/receipt and safe
  unknown-outcome semantics. The journal's five rewritten scenario tests and
  codec/identity/admission/lock-wait suites remain present and pass.

## Actual final verification

Commands ran from umbrella root, using the existing isolated PostgreSQL 18.6
cluster at /tmp/beamlet-storage-a-pg, Unix socket, port 55481. It was restarted
explicitly for this check; fixtures create/drop only their own test databases.
The cluster was stopped after the final test run. SQLite reported 3.53.4.

- `BEAMLET_PG_SOCKET_DIR=/tmp/beamlet-storage-a-pg/socket BEAMLET_PG_PORT=55481 mix test apps/beamlet_storage/test --seed 631927`: **72 passed**, no exclusions/skipped adapter. Shared contract: 18 SQLite + 19 PostgreSQL cases, plus 35 other Storage cases. Log: /tmp/beamlet-storage-check-tests.log.
- `mix credo --strict --all`: **pass**, 199 files, 2452 modules/functions, no findings. Log: /tmp/beamlet-storage-check-credo.log.
- `mix format --check-formatted`: **pass**. Log: /tmp/beamlet-storage-check-format.log.
- `git diff --check`: **pass**.
- `mix compile --warnings-as-errors`: **fails at the documented intermediate Agent integration boundary**, exactly prepare_batch/2 (durable.ex:289), consume_result/2 (:336), fork/2 (:634). Log: /tmp/beamlet-storage-check-compile.log. Storage compiles during focused tests. These old callers were not repaired or shimmed in A.

Intermediate strict Credo runs failed on new nesting/quote size and were fixed
with helper extraction; those runs are not passing evidence. Driver termination
and SQLite lock errors in the passing test log are intentional negative controls.
The existing test/support file-filter warning and old Agent-call warnings remain
visible rather than suppressed. LSP feedback was supplemental; the test/compiler
and static gates above establish the reported outcomes.

## Concrete B/C handoff and remaining boundaries

Use Storage README and research/handoff.md for the complete signature inventory.
These corrections supersede the original handoff where applicable:

- B must claim the committed prepared identity once; already accepted work refuses
  claim even when the original preparation command replays. PostgreSQL claim now
  serializes checked generation/acceptance facts with concurrent writes. A claim
  committed before activation still cannot be revoked by a database CAS: B/C must
  retire old senders; send_claimed unknown never authorizes another admit.
- B's independent `prepare/2` is strictly generic: no Agent role, ownership/turn/
  step/ordinal/tool-call metadata or nonempty sources. Model/tool orchestration
  uses `AgentRecords.prepare_operations/2`, preserving original input first.
- C must supply position `{agent_id, lock_version, generation}`, explicit command
  UUID, exact typed source list, and accepted digest/consumption kind. New writes
  in orchestration/join/advance must reference the same Agent's Operations and
  locally available verified artifacts. Return values/outer signatures are unchanged.
- Turn readers must pass the returned first-sequence cursor to after_first_seq.
- C owns supported event/reducer decoding, bounded full reduction, generation
  activation and unknown blockers. Checkpoint body-key validation is structural,
  not arbitrary text interpretation; safe_to_fork is not independently certified
  by Storage and must be decided by the reducer/fork layer.
- D must implement reference-based fork/inherited source authorization and closure
  export. Current sources deliberately support only owned input/consumed accepted
  references; no copied-transcript fallback exists.

Full umbrella tests, named distributed peers, release/e2e, Dialyzer, physical-host,
power-loss and complete restore/fork/export acceptance were not run here. No
passing full-system claim is made. Shared specs still need integration-time
synchronization while preserving their pre-existing edits.
