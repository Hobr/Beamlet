# Operation Contracts and Multi-node Runtime — Execution Plan

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
This child is planning only. The parent final summary must be approved before
activation; no product code or implementation dispatch is authorized yet.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Activation Gate

No child dependency. This is the first implementation target after parent-plan approval.

User approval of the complete parent/child plan authorizes sequential activation
without asking again for unchanged steps. Start only this child when its
prerequisites pass. Load before-dev context; one implementation writer at a time,
then Trellis quality check. Worker agents do not commit.

## Ordered Checklist

- [ ] Implement validated contracts and non-AI handler fixtures.
- [ ] Implement opt-in shared discovery/directory/coordinator infrastructure.
- [ ] Implement execution gateway, local admission and MFA worker wrapper.
- [ ] Implement lifecycle, progress credits, retention, deadlines and timer-driven cancellation.
- [ ] Exercise real VM success, concurrent capacity, uncertain admission/partition and infrastructure failure.
- [ ] Perform focused/full checks and document consumer contracts before child 3.
- [ ] Run active changed-file diagnostics where available; absent LSP coverage is recorded.
- [ ] Review parent AC mapping and this child acceptance; record verification/handoff.
- [ ] Update applicable executable-contract specs and follow finish-work process.

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
