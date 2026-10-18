# B Runtime implementation handoff

Implemented on `refactor/durable-rebuild` after A's independent 72-test check.
No Agent rewrite, commits, pushes, merges, task-status changes or archive actions.
Existing A changes and earlier shared design/spec edits were preserved. This is an
intermediate integration delivery; C/D and parent acceptance remain required.

## APIs for C

The executable integration example and guarantees are in
`apps/beamlet_runtime/README.md`; Storage parameter schemas remain in its README.

1. Build an `Actions.Operation` with the **complete effective logical request**.
   Payload must already include model/options/configuration, schemas, tool inputs
   and any provider settings that determine the request. Runtime never resolves
   provider settings or prompt policy. Credentials are the transient dedicated
   Operation field; they cannot appear in the description or sources.
2. Use `Persistence.description(operation)` verbatim for the atom-key member's
   `operation.description` in `AgentRecords.prepare_operations/2`. Canonical JSON
   contains kind/protocol_version/payload/budget/claims and safety containing
   Operation metadata, capabilities, environment and allowed node labels. Store
   ordered validated `sources` beside description. Policy/version/transformation
   provenance may be fixed in Operation metadata; sources are validated by A.
3. Prepare model **and** tool/summary work with owner_agent_id, turn_id, step_id,
   role and ordinal through that atomic Agent API. Do not use independent prepare
   for model work; independent Runtime work remains generic and ownerless.
4. Call `Runtime.submit(operation, persistence: persistence, prepared: member,
   owner: owner_pid, sink: sink_pid, require_live_owner: true)`, where member is
   exactly a returned `committed["operations"]` member. String-key identities:
   operation_id, attempt_id, description_digest, attempt_version, lock_version.
   Runtime reads authority and checks request equality, versions, exact attempt,
   prepared state, executor/boot and no accepted output. No new Operation is made.
5. Persistence has no Agent position/accept_seq protocol. Optional
   `owner: %{agent_id: uuid, turn_id: uuid, step_id: string}` binds identity only;
   it cannot be used with independent preparation. Old version-shaped owners are
   rejected, not translated. The struct field remains for this new identity API.
6. Acceptance is `OperationRecords.accept_result/2` using Operation version only.
   Read accepted_digest from the authority row and explicitly call
   `AgentRecords.consume_results/2` using the current Agent position and model_result,
   tool_result or evidence_resolution consumption kind. Runtime never advances
   Agent events, consumes results, or reserves Agent sequence positions.

C must retire old senders on activation. Storage rejects a new claim from an old
owner generation, but a claim already committed before activation is not revoked
by a later database CAS. A send_claimed row, including an unknown acknowledgement,
never grants permission for another admit. No retry/failover API was added.

## Changes and safety

- Generic prepare uses A's strict operation+sources+attempt shape; removed old event
  and Agent attributes. Canonical request description now also fixes placement and
  nonsecret metadata. Boolean/nil JSON values remain boolean/nil in receipts.
- Coordinator claims before selection or terminal acceptance. Failed/duplicate
  claims stop without accepting a synthetic error against the original Worker.
  Even pre-dispatch owner/deadline messages cannot accept an unclaimed Result.
- Independent acceptance, evidence-first/accepted-before-notify, and source stop
  classification remain intact. Failed acceptance hides the Result from status and
  sink. Unknown acceptance is reconciled by stable ID and exact result/evidence,
  without retrying the write.
- Durable completion requires a receipt with matching authority/Operation/attempt/
  executor/boot/request digest and matching result, plus a recomputed receipt digest.
  A bare ephemeral completion cannot satisfy a durable Coordinator. Late correlated
  receipts add evidence without replacing accepted output or notifying again.
- Gateway treats journal unavailable separately from explicit not-found; only the
  latter permits initial insertion. Duplicate-admission replies are uncertain,
  not proof of nonexecution. Restart unknown, insert-once intent and no Worker
  reconstruction remain unchanged.
- Full durable admission tuple (including credentials and durable identity) and
  completion tuple (including the full receipt) obey existing deployment byte
  caps. Oversize output becomes an explicit invalid-result error before terminal
  journaling; if even that envelope cannot fit, it is unrecorded/uncertain.
  No limits or timeouts were enlarged. Ephemeral existing cap semantics remain.
- `Runtime.evidence/3` additionally checks attempt binding; journal offline and
  absent remain distinct. Accepted body is always read from authority, without a
  coordinator or live executor requirement.
- Essential Storage correction in `Transaction`: stopped Ecto Repo lookup raises
  RuntimeError rather than the caught driver errors. Only that specific lookup
  prefix is classified unavailable/unknown; other runtime exceptions re-raise.
  Real authority-stop and journal-offline regressions exposed and now cover it.

## Verification and remaining integration

Final actual results are in `research/check-evidence.md`: Actions28, Storage72
(real SQLite + PostgreSQL), Runtime64 local +7 actual named peers, strict Credo,
format and diff whitespace pass. Root warning-fatal compile remains blocked by
exactly the three removed old Agent calls assigned to C/D. No full umbrella,
release/e2e, Dialyzer, physical-host or power-loss claim is made. Local checklist
review was performed; no independent checker was spawned under the recursion guard.
