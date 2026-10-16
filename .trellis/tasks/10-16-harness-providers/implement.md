# Independent Harness and Concrete Providers — Execution Plan

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Activation Gate

No implementation dependency on child 1; default execution follows its gate to preserve one-writer sequencing. Child 3 needs both children complete.

User approval of the complete parent/child plan authorizes sequential activation
without asking again for unchanged steps. Start only this child when its
prerequisites pass. Load before-dev context; one implementation writer at a time,
then Trellis quality check. Worker agents do not commit.

## Ordered Checklist

- [x] Implement native interfaces/catalogue/context and deterministic fixtures.
- [x] Define and enforce documented argument/schema subset and full-batch validation.
- [x] Add narrowly scoped Req/Jason/test dependency and lock changes.
- [x] Implement complete bounded HTTP adapter and local wire/transport fixture tests.
- [x] Implement read-only workspace Tool and path/type/output/cleanup tests.
- [x] Run independent Harness quality gate and record adapter-facing handoff.
- [x] Run active changed-file diagnostics where available; absent LSP coverage is recorded.
- [x] Review parent AC mapping and this child acceptance; record verification/handoff.
- [x] Parent delivery: update native Harness executable-contract specs and overview links.
- [ ] Commit/archive bookkeeping (deferred to final delivery batch).

Parent accepted the scoped implementation/check gate on 2026-10-16, based on
check-report.md, verification.md, final handoff.md and source-contract inspection.
No unresolved scoped blocker; active LSP remains unavailable, not clean. Child 3
may consume both verified handoffs; later physical-host/live-provider evidence
is not established by this gate.

## Validation

```bash
cd apps/beamlet_harness && mix test
# Root checks also include actual dependency closure and lock diff review.
```

Also run parent applicable formatting/compile/static/dependency/whitespace gates.
Commands are prospective, not passing evidence. For distributed tests, use isolated
names/cookies, bounded peer startup and teardown, message barriers and alternative
control for partition tests. Report actual executed test counts and skip reasons.
Consult parent implement.md for full integration and external-evidence requirements.

## Pause / Rollback Point

No live paid requests. Pause for incompatible provider shape rather than guessing; no HTTP automatic retries. Do not label lstat checks as an OS sandbox.
On failure, preserve unrelated source/index changes and repair the owning seam;
do not continue adding dependent features to conceal a failed gate.

## Implementation record

Implemented by sole Harness writer; see `verification.md` for actual commands,
counts and diagnostic caveats, and `handoff.md` for child-3 APIs/limits. Independent scoped review is complete (see check-report.md); checklist completion
records child evidence, while parent integration approval remains separate. No task-state/index/commit/archive changes were made.


## Independent check record

Scoped review and repairs completed; check-report.md compares all child acceptance
criteria and parent-owned seams. Final verification: independent Harness 26 tests,
umbrella 66 passed / four unchanged Runtime distributed exclusions, compile,
umbrella format, strict scoped Credo, dependency/xref inspection and checked-PLT
Dialyzer all passed. Active LSP remains unavailable, explicitly not clean. Final
handoff includes strict profile/request/metadata subset and sentinel semantics.
Parent delivery/spec/state/commit steps remain outside this worker's scope.
