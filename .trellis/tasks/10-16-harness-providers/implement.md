# Independent Harness and Concrete Providers — Execution Plan

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
This child is planning only. The parent final summary must be approved before
activation; no product code or implementation dispatch is authorized yet.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Activation Gate

No implementation dependency on child 1; default execution follows its gate to preserve one-writer sequencing. Child 3 needs both children complete.

User approval of the complete parent/child plan authorizes sequential activation
without asking again for unchanged steps. Start only this child when its
prerequisites pass. Load before-dev context; one implementation writer at a time,
then Trellis quality check. Worker agents do not commit.

## Ordered Checklist

- [ ] Implement native interfaces/catalogue/context and deterministic fixtures.
- [ ] Define and enforce documented argument/schema subset and full-batch validation.
- [ ] Add narrowly scoped Req/Jason/test dependency and lock changes.
- [ ] Implement complete bounded HTTP adapter and local wire/transport fixture tests.
- [ ] Implement read-only workspace Tool and path/type/output/cleanup tests.
- [ ] Run independent Harness quality gate and record adapter-facing handoff.
- [ ] Run active changed-file diagnostics where available; absent LSP coverage is recorded.
- [ ] Review parent AC mapping and this child acceptance; record verification/handoff.
- [ ] Update applicable executable-contract specs and follow finish-work process.

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
