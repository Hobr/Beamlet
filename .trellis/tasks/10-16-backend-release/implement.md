# Backend CLI, Release and Multi-machine Acceptance — Execution Plan

## Final scope disposition — user-approved removal

The user instructed: "取消跨物理主机验收这一要求, 继续开展后续工作".
This supersedes earlier pending/deferred physical-gate statements below. Child AC5
is removed; parent AC2/AC11 require the delivered multi-VM/release/deployment
evidence only. Physical testing was not executed and is not claimed. All remaining
implementation/check gates are accepted (123 ordinary tests;7 distributed tests at
two seeds; copied named release/closure/control checks). No source changed for this
scope reduction. Proceed to Phase3.4 commit plan, then archive/journal bookkeeping.
Earlier records below remain historical where they conflict with this disposition.

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Parent Local Gate Acceptance — 2026-10-16

Parent read independent verification/check-report/handoff, Runtime repair evidence
and final CLI/release/config/deployment source. Accept the local implementation/check
gate:123 ordinary tests,7 distributed at seeds719916 and631927, copied named role
start/RPC/stop and shipped closure, compile/format/Credo/existing-PLT Dialyzer pass.
Default Web secret/CSP retained. Former aggregate blocker closed; historical reason
unknown, controlled stale-capacity cause preserved. Backend executable specs synced.
No pending supervisor request. Physical childAC5/parentAC2,AC11 remains pending;
this is not whole-child completion or archive. Commit/finish bookkeeping deferred.

## Activation Gate

Prerequisites satisfied on 2026-10-16: parent accepted children1–3 scoped
implementation/check gates and published actual handoffs/executable specs. Child3's
final independent86-test gate (seed631927) includes all six distributed cases;
public Runtime admission and bounded lifecycle contracts are accepted. Consume
all three actual handoffs plus operation-runtime/harness-providers/agent-orchestration
specs. Commit/archive bookkeeping remains deferred to final delivery. Parent owns
cross-child sign-off and remains incomplete without required physical-host evidence.

User approval of the complete parent/child plan authorizes sequential activation
without asking again for unchanged steps. Start only this child when its
prerequisites pass. Load before-dev context; one implementation writer at a time,
then Trellis quality check. Worker agents do not commit.

## Ordered Checklist

- [x] Consume completed child interfaces; implement thin CLI/IEx examples.
- [x] Implement backend release/runtime config and preserve Web secret validation.
- [x] Inspect shipped closure and boot copied release without source/web secrets.
- [x] Implement deterministic actual-VM end-to-end and local HTTP transport scenarios.
- [x] Write multi-host deployment/teardown/verification scripts and runbook.
- [x] Physical-host acceptance requirement removed by user; not executed or claimed.
- [x] Run local quality gates; parent AC/evidence matrix is in ../10-16-distributed-agent-mvp/integration-review.md. Physical gate removed by user.
- [x] Run active changed-file diagnostics where available; absent LSP coverage is recorded.
- [x] Review parent AC mapping and this child acceptance; record verification/handoff.
- [x] Update applicable executable-contract specs (backend-release.md and linked overviews).
- [ ] Follow final commit/finish-work process (external gate removed; awaiting batched commit confirmation).

## Validation

```bash
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_node
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

## Aggregate Distributed Gate Repair Authorization

Parent inspected child4 reports and /tmp/child4-distributed-final.log. The Runtime
remote execution test fails at its second sequential submission (line78), twice
in the aggregate suite; same-seed focused success does not close the gate.
Authorize a single Runtime-seam implement worker to capture safe failure reasons,
diagnose admission/discovery/accounting ordering, and repair only Runtime distributed
tests/support if the evidence establishes a missing readiness/capacity barrier.
No weakened assertions, sleeps or submission retries. Product Runtime changes need
an evidence-backed parent decision first. No child4/source cross-seam edits in this
repair. Record before/after evidence in aggregate-runtime-repair.md here; rerun the
failed full distributed gate. Independent child4 review follows the repair.

## Pause / Rollback Point

Never mark physical or live-provider checks passed from fixtures/peers. Do not print keys/cookies/workspace content in shared evidence. Missing external access is a specific blocked gate, not a reason to abandon other deliverables.
On failure, preserve unrelated source/index changes and repair the owning seam;
do not continue adding dependent features to conceal a failed gate.
