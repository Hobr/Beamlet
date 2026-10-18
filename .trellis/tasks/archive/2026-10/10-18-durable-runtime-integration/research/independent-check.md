# Independent B review

## Outcome

Independently reviewed Runtime B and the necessary Storage integration against B's
PRD/design/plan, curated check context, the parent and target designs, and A/B
handoffs. Applied the trellis-check and pre-development checklists directly; no
nested agents, Agent edits, compatibility shims, commits, archival or task-status
changes. No remaining issue was identified within the reviewed B scope after the
fix below. This is intermediate acceptance; C/D and parent gates remain open.

## Finding fixed: keyword persistence bypassed durable admission

`Runtime.submit/2` called `coordinators_available/1` on the raw persistence option
before `Persistence.new/1`. The keyword input accepted by `Persistence.new/1` fell
through the permissive clause, bypassing both host admission and the durable
coordinator-presence check. With a recorded storage failure but a healthy Repo,
submit could commit another Operation and return a live coordinator despite
admission being refused.

The new regression reproduced this: keyword input returned `{:ok, ref}` where
`{:error, :unavailable}` was required. The original red result is retained at
`/tmp/beamlet-b-independent-red.log` (2/3 passed, one failure).

Fix: normalize persistence before checking coordinator/admission availability;
remove the now-unreachable fallback clause. Two regressions cover struct and
keyword inputs while the actual datasets remain writable. They assert refusal,
unchanged Operation count, and no Handler invocation. No public signature changed.

Files changed by this independent checker:

- `apps/beamlet_runtime/lib/beamlet/runtime.ex`
- `apps/beamlet_runtime/test/beamlet/durable_admission_test.exs`
- this evidence file

## Reviewed invariants

- Prepared requests are read from authority and matched against complete logical
  description, digest, Operation/attempt versions, prepared state and executor/boot;
  optional supplied owner binds Agent/turn/step. Existing fixed sources remain
  Storage-owned and validated during atomic preparation.
- Claim occurs before selection/admission and terminal acceptance. Duplicate or
  stale-generation claims stop without accepting a synthetic losing Result.
  `send_claimed` and restart-unknown attempts cannot authorize another Worker.
- Gateway verifies the full durable envelope and request digest, writes intent
  before task creation, distinguishes journal absence from outage, and retains
  durable attempt deduplication across boot. Evidence reads start no Worker.
- Authority stores evidence and accepted Result before sink completion. Failed
  acceptance hides the Result from status and sink. Unknown acceptance commits
  reconcile by stable identity/content without retrying the write.
- Receipt identity/content is bound to authority/Operation/attempt/executor/boot,
  request digest and executor result. Coordinator observation metadata may differ
  from executor receipt metadata intentionally. Late receipts add evidence and do
  not replace accepted output or cause a second terminal delivery.
- Dedicated credentials are transient; accepted content remains authority-readable
  with journal offline. Gateway and Coordinator preserve existing size caps and
  first-stop/actual-termination distinctions and existing capacity/helper cleanup.
- Storage transaction handling of stopped Ecto Repo lookup is narrowly scoped to
  that RuntimeError prefix; unrelated runtime exceptions re-raise.

## Actual verification

All test commands ran from the umbrella root at seed 631927.

| Gate | Result | Log |
| --- | --- | --- |
| `BEAMLET_PG_SOCKET_DIR=/tmp/beamlet-storage-a-pg/socket BEAMLET_PG_PORT=55481 mix test apps/beamlet_storage/test apps/beamlet_runtime/test apps/beamlet_actions/test --seed 631927` | Actions **28 passed**, Storage **72 passed**, Runtime **66 passed / 7 distributed excluded** | `/tmp/beamlet-b-independent-all.log` |
| `elixir --sname beamlet_b_independent --cookie beamlet_b_independent_cookie --erl '+S 2:2' -S mix test apps/beamlet_runtime/test --only distributed --seed 631927` | **7 passed / 66 ordinary excluded**, actual named peer VMs | `/tmp/beamlet-b-independent-distributed.log` |
| `mix credo --strict --all` | exit 0, 199 source files, no issues | `/tmp/beamlet-b-independent-credo.log` |
| `mix format --check-formatted` | exit 0 after formatting the new tests | `/tmp/beamlet-b-independent-format.log` |
| `git diff --check` | exit 0 | command output empty |
| `mix compile --warnings-as-errors` | fails at the known C/D boundary, exactly three old Agent calls | `/tmp/beamlet-b-independent-compile.log` |

The compile failures are `OperationRecords.prepare_batch/2`,
`AgentRecords.consume_result/2`, and `AgentRecords.fork/2` in Agent Durable.
Runtime no longer introduces an unused-clause warning after normalization.

PostgreSQL used only the existing isolated cluster `/tmp/beamlet-storage-a-pg`,
PostgreSQL 18.6, Unix socket port 55481. It was stopped before this review and was
started for the real adapter run, then stopped again. No real datasets were used.

## Handoff to C

No API changes beyond the existing B handoff are required. Both supported
persistence representations now honor the same durable admission checks. C must
still use the exact Storage prepared member, complete
`Persistence.description(operation)`, optional identity-only owner, independent
Operation acceptance, and explicit digest-bound Agent result consumption.

No full umbrella/release/e2e, Dialyzer, power-loss or physical-host acceptance is
claimed. The named peers provide same-host distributed evidence. Existing C/D
compile blockers remain explicit and must be resolved without old-API shims.
