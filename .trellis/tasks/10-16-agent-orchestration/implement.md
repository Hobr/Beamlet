# Agent Orchestration and Node Role Composition — Execution Plan

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
This child is planning only. The parent final summary must be approved before
activation; no product code or implementation dispatch is authorized yet.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Activation Gate

BLOCKED until child 1 operation-runtime and child 2 harness-providers pass their gates and publish actual contract handoffs. No broad speculative adapter implementation before both.

User approval of the complete parent/child plan authorizes sequential activation
without asking again for unchanged steps. Start only this child when its
prerequisites pass. Load before-dev context; one implementation writer at a time,
then Trellis quality check. Worker agents do not commit.

## Ordered Checklist

- [ ] Verify child 1/2 handoffs; implement isolated caller/executor integration adapters.
- [ ] Implement authority identity island, responsive Agent commands/loop and parallel joins.
- [ ] Implement bounded snapshots/subscriptions, context/step/pending limits and turn-stop races.
- [ ] Implement API-driven delegation/peer correlation/monitor/cleanup semantics.
- [ ] Implement Node role configuration, provider lifecycle/readiness and coupled supervision.
- [ ] Run multi-node/fault/role tests and publish CLI/release-facing contracts.
- [ ] Run active changed-file diagnostics where available; absent LSP coverage is recorded.
- [ ] Review parent AC mapping and this child acceptance; record verification/handoff.
- [ ] Update applicable executable-contract specs and follow finish-work process.

## Validation

```bash
cd apps/beamlet_agent && mix test
cd apps/beamlet_node && mix test
# Root distributed-tag run must exercise actual loop, delegation and role faults.
```

Also run parent applicable formatting/compile/static/dependency/whitespace gates.
Commands are prospective, not passing evidence. For distributed tests, use isolated
names/cookies, bounded peer startup and teardown, message barriers and alternative
control for partition tests. Report actual executed test counts and skip reasons.
Consult parent implement.md for full integration and external-evidence requirements.

## Pause / Rollback Point

Do not block a GenServer callback awaiting model/Tool/child completion. Do not reserve executor capacity while waiting for Agents. Pause if contract changes would weaken result identity or introduce runtime→Harness dependencies.
On failure, preserve unrelated source/index changes and repair the owning seam;
do not continue adding dependent features to conceal a failed gate.
