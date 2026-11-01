# Rune-first Codemode Implementation Plan

## Authorization and Ordering

This is a paused reference plan. The user clarified that the current scope
is to freeze the high-level direction only. Do not run code experiments,
edit product code, execute the validation commands, dispatch implementation,
or run task.py start without fresh authorization for that work.

The milestones below are tentative future steps, not an approved execution
sequence. Retaining them does not authorize a Rune spike or a detailed backend
implementation. All implementation boxes remain unchecked.

## 0. Before Activation

- [ ] Review prd.md, design.md, this plan, and the evidence note with the user.
- [ ] Confirm the review did not change scope or the Rune-only decision.
- [ ] Load the current phase 1.4 instructions and trellis-before-dev guidelines.
- [ ] Reread Git status, manifests, lockfile, specs, and existing Console code;
      preserve changes made after the recorded baseline.
- [ ] Validate both JSONL context manifests and exact resolved dependency APIs.
- [ ] Obtain fresh approval after material planning changes.
- [ ] Only then run task.py start and enter implementation.

## 1. Rune Feasibility Gate

Before a broad backend implementation, use disposable test capabilities:

- [ ] Register a synchronous native host boundary that records initiation order
      before returning its awaitable.
- [ ] Exercise unawaited calls, reverse await order, loops, repeated equal
      arguments, joins, selection/races, errors, and delayed completions.
- [ ] Prove that lazy Future polling does not allocate invocation identity.
- [ ] Recreate a VM under the same logical Operation and match a committed
      invocation/delivery prefix without reexecuting covered capabilities.
- [ ] Reject changed definitions, shortened prefixes, changed control flow,
      and incompatible fingerprints before uncovered effects.
- [ ] Verify the execution threading model, instruction budget, cancellation
      of a dead loop, output caps, and allocation-limit coverage.
- [ ] Record limitations in the evidence note and tests.

Gate: if Rune cannot satisfy stable identity or bounded guest execution, stop
for review. Do not switch engines or weaken the PRD without user approval.
A replay harness is not a claim of arbitrary transparent program recovery.

## 2. Model and Public Boundary

- [ ] Define typed operation/attempt/report identities, immutable definitions,
      provenance, evidence, cancellation intent, and adoption decisions.
- [ ] Define bounded structured-data codecs, canonical fingerprints, and
      protocol/host compatibility checks.
- [ ] Separate Client from Host and local access from transport implementation.
- [ ] Add only dependencies actually consumed by the appropriate crate/feature;
      inherit tempfile/proptest as dev-dependencies where used.
- [ ] Keep a client-only build free of active roles and storage/engine services.

Gate: model and serialization tests contain no Agent or Rune runtime types.

## 3. SQLite Facts and Transactional Delivery

- [ ] Add versioned schema/migration code through the selected SeaORM layout.
- [ ] Implement atomic Authority admission and invocation uniqueness.
- [ ] Implement Work receipt deduplication and durable effect-entry evidence.
- [ ] Implement report commitment, delivery responsibility, and adoption.
- [ ] Implement guest-delivery journaling and execution-generation checks.
- [ ] Test fresh databases, upgrade paths, uniqueness races, and write failures.

Gate: crash/reopen tests prove each promised local transaction; no independent
save sequence stands in for a required atomic commitment.

## 4. Role Actors and Bounded Execution

- [ ] Add one enabled role actor of each kind per Runtime.
- [ ] Track bounded execution tasks and turn completions/panics into evidence.
- [ ] Reconcile restarted actors with existing tasks and durable receipts.
- [ ] Integrate the proven Rune host wrapper and journal-driven result release.
- [ ] Implement completion/deadline behavior and retained unresolved calls.
- [ ] Ensure retries require Authority policy rather than supervisor defaults.

Gate: slow or non-yielding execution does not block actor control messages;
actor restart alone never starts a replacement effectful Attempt.

## 5. Kameo Remote and Node Hosting

- [ ] Verify resolved Kameo network lifecycle and custom identity APIs.
- [ ] If needed, add a directly compatible libp2p dependency; do not introduce
      an unrelated newer libp2p merely because it is available.
- [ ] Configure persistent Node identity, trusted peers, limits, and storage.
- [ ] Make durable acceptance precede its success reply.
- [ ] Retry delivery by stable message/Attempt identity with bounded backoff.
- [ ] Test two Node subprocesses, disconnects, duplicate delivery, and restart.
- [ ] Preserve the transport boundary without implementing MQTT/HTTP/WS.

Gate: remote behavior uses the same commitments as local access and does not
rely on two isolated Kameo Swarms inside one process.

## 6. Console Vertical Slice and Observability

- [ ] Inspect and reuse the current Console scaffold; avoid an unrelated rewrite.
- [ ] Expose script submission and operation/attempt/evidence inspection through
      the shared Client boundary, including noninteractive validation.
- [ ] Show unknown outcomes, cancellation intent, and unresolved/late reports.
- [ ] Install collectors in applications and emit redacted events/metrics from
      the library without installing globals.
- [ ] Document how to run Node and submit a script without any model service.

Gate: a user can reproduce the acceptance scenario through Console, not just
through private test helpers.

## 7. Full Acceptance and Review

- [ ] Run a script with three concurrent calls: two completed and one in a
      possible-effect window when a process is killed.
- [ ] Restart and inspect original logical identities, completed facts, and
      the remaining unknown; never silently retry the unknown call.
- [ ] Reconstruct the controlled guest prefix and verify matching, mismatch
      rejection, committed result order, and retained reports.
- [ ] Inject crashes before/after admission, effect entry, report commitment,
      and guest-delivery commitment.
- [ ] Test cancellation, dropped awaitables, script return, dead loops,
      overload, disk/write failure, actor restart, and late reports.
- [ ] Check every PRD acceptance criterion against an observable test.
- [ ] Run trellis-check and capture actual implementation-backed conventions
      in specs without treating the current templates as established practice.

## Validation Commands

Run the appropriate subset at each milestone and the complete set before
claiming implementation completion. These commands were planned, not run by
the documentation-only creation turn:

```bash
cargo fmt --all -- --check
cargo check --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo nextest run --workspace --all-features
cargo test --workspace --doc --all-features
cargo deny check
cargo about generate --workspace about.hbs > /tmp/beamlet-licenses.html
cargo doc --workspace --no-deps
git diff --check
```

Add explicit client-only and feature-matrix checks once actual feature names
exist; do not invent commands that cannot yet run. Tests must include real
subprocess termination and database reopen, not only injected Rust errors.

## Risk and Rollback Points

- Stop after the Rune spike if identity, scheduling, or preemption is unsound.
- Commit/restore schema and codec changes as coherent units; test against copies
  of persistent data, not operator databases.
- Never use destructive Git cleanup to remove user changes.
- On runtime rollback, stop admissions and preserve durable delivery/evidence.
- If a protocol or public behavior changes materially, update the artifacts
  and obtain another planning review before proceeding.

## Completion Boundary

The user narrowed this task to a high-level design freeze and requested its
closure after the plan was recorded. Archive this task as documentation-only
completion. All backend milestones and implementation acceptance criteria above
remain deferred and unchecked; no runtime validation or implementation success
is claimed. Future experiments or implementation require a new task and fresh
authorization.
