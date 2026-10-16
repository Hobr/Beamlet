# Operation Contracts and Multi-node Runtime — Execution Plan

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Activation Gate

No child dependency. This is the first implementation target after parent-plan approval.

User approval of the complete parent/child plan authorizes sequential activation
without asking again for unchanged steps. Start only this child when its
prerequisites pass. Load before-dev context; one implementation writer at a time,
then Trellis quality check. Worker agents do not commit.

## Ordered Checklist

- [x] Implement validated contracts and non-AI handler fixtures.
- [x] Implement opt-in shared discovery/directory/coordinator infrastructure.
- [x] Implement execution gateway, local admission and MFA worker wrapper.
- [x] Implement lifecycle, progress credits, retention, deadlines and timer-driven cancellation.
- [x] Exercise real VM success, concurrent capacity, uncertain admission/partition and infrastructure failure.
- [x] Perform focused/full checks and document consumer contracts before child 3.
- [x] Run active changed-file diagnostics where available; absent LSP coverage is recorded.
- [x] Review parent AC mapping and this child acceptance; record verification/handoff.
- [x] Update applicable executable-contract specs.
- [ ] Commit and follow finish-work process (deferred to final delivery batch).

Parent accepted this child's implementation/check gate on 2026-10-16 after report
and source-contract review. `.trellis/spec/backend/operation-runtime.md` now records
actual APIs, limits, failure semantics and required tests; linked overview/state/
error/quality specs were corrected. A parent active LSP probe checked 11 source
files: all timed out, none confirmed clean. Compile/tests/Credo and existing-PLT
analysis remain the actual evidence. Archival is pending commit bookkeeping and
does not block the independently verifiable Harness implementation gate.

Implementation/check evidence is in `verification.md`; the actual consumer API is
in `handoff.md`. Checked items record work performed, not child acceptance. Scoped
check repaired deployment byte limits, registration/report bounds, live progress,
membership/endpoint monitoring and lifecycle defects; see `check-report.md` for
findings and final evidence. Spec/finish operations remain
with the parent because this worker's write scope excludes backend specs and git
operations.

## Validation

```bash
cd apps/beamlet_actions && mix test
cd apps/beamlet_runtime && mix test
# From repository root, explicit distributed-tag run:
elixir --sname beamlet_tests --cookie <isolated-test-cookie> -S mix test --only distributed
```

Also run parent applicable formatting/compile/static/dependency/whitespace gates.
Commands are prospective, not passing evidence. For distributed tests, use isolated
names/cookies, bounded peer startup and teardown, message barriers and alternative
control for partition tests. Report actual executed test counts and skip reasons.
Consult parent implement.md for full integration and external-evidence requirements.

## Pause / Rollback Point

Do not add Agent/provider imports to runtime. Pause if lifecycle tests cannot distinguish a definite rejection from uncertain admission; never solve it with retries.
On failure, preserve unrelated source/index changes and repair the owning seam;
do not continue adding dependent features to conceal a failed gate.
