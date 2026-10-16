# Backend CLI, Release and Multi-machine Acceptance — Execution Plan

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
This child is planning only. The parent final summary must be approved before
activation; no product code or implementation dispatch is authorized yet.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Activation Gate

BLOCKED until children 1–3 pass their gates and publish actual interfaces. Parent owns final cross-child AC sign-off and remains incomplete without required physical-host evidence.

User approval of the complete parent/child plan authorizes sequential activation
without asking again for unchanged steps. Start only this child when its
prerequisites pass. Load before-dev context; one implementation writer at a time,
then Trellis quality check. Worker agents do not commit.

## Ordered Checklist

- [ ] Consume completed child interfaces; implement thin CLI/IEx examples.
- [ ] Implement backend release/runtime config and preserve Web secret validation.
- [ ] Inspect shipped closure and boot copied release without source/web secrets.
- [ ] Implement deterministic actual-VM end-to-end and local HTTP transport scenarios.
- [ ] Write multi-host deployment/teardown/verification scripts and runbook.
- [ ] Run physical-host acceptance when hosts are accessible; record or block honestly.
- [ ] Run full quality gates and deliver parent AC/evidence matrix.
- [ ] Run active changed-file diagnostics where available; absent LSP coverage is recorded.
- [ ] Review parent AC mapping and this child acceptance; record verification/handoff.
- [ ] Update applicable executable-contract specs and follow finish-work process.

## Validation

```bash
MIX_ENV=prod mix release beamlet_node
mix test
elixir --sname beamlet_tests --cookie <isolated-test-cookie> -S mix test --only distributed
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix sobelow
mix xref graph --format cycles
```

Also run parent applicable formatting/compile/static/dependency/whitespace gates.
Commands are prospective, not passing evidence. For distributed tests, use isolated
names/cookies, bounded peer startup and teardown, message barriers and alternative
control for partition tests. Report actual executed test counts and skip reasons.
Consult parent implement.md for full integration and external-evidence requirements.

## Pause / Rollback Point

Never mark physical or live-provider checks passed from fixtures/peers. Do not print keys/cookies/workspace content in shared evidence. Missing external access is a specific blocked gate, not a reason to abandon other deliverables.
On failure, preserve unrelated source/index changes and repair the owning seam;
do not continue adding dependent features to conceal a failed gate.
