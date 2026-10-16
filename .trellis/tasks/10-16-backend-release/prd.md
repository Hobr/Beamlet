# Backend CLI, Release and Multi-machine Acceptance

## Goal

Deliver usable IEx/CLI entry points and a backend release, with reproducible automated multi-VM acceptance and deployment instructions.

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies

Prerequisites satisfied on 2026-10-16: parent accepted children1–3 scoped
implementation/check gates and published actual handoffs/executable specs. Child3's
final independent86-test gate (seed631927) includes all six distributed cases;
public Runtime admission and bounded lifecycle contracts are accepted. Consume
all three actual handoffs plus operation-runtime/harness-providers/agent-orchestration
specs. Commit/archive bookkeeping remains deferred to final delivery. Parent owns
cross-child sign-off. User cancelled the physical-host acceptance requirement;
local gates pass and final commit/archive bookkeeping may proceed.

## Requirements

1. Own parent R2/R4/R6/R7 delivery portions and AC2/AC5/AC10–AC12. Wrap Agent API for authority selection/input/watch/snapshot/stop and delegation/peer examples.
2. Build a production Node release with no Phoenix/Web artifacts/listeners or dummy web secret; authority needs no executor credential/root.
3. Retain existing Web scaffold/CSP/production secret fail-fast behavior while isolating backend runtime configuration.
4. Provide repeatable trusted-cluster deployment/config/teardown instructions and scripts for at least two physical hosts, with B authority and C executor on different hosts.
5. Record automated fixtures, same-host peers, real physical hosts and optional live-provider checks separately; do not infer unavailable external evidence.

## Acceptance Criteria

- AC1: IEx/CLI controls an explicitly remote authority, displays bounded progress/result/unknown states and stops work without owning a second loop.
- AC2: Built release boots copied outside source/deps without SECRET_KEY_BASE; inspect .rel/.app/lib closure to prove Web/Phoenix/PubSub/Bandit absence. Executor-only/authority-only boots have only their configured role services.
- AC3: Enabled production Web still fails for missing secret and existing Web CSP tests pass.
- AC4: Automated A/B/C independent-VM end-to-end test completes model→workspace Tool→model and fault/control scenarios, with cleanup and no wrong-node fallback.
- AC5: Removed by explicit user instruction ("取消跨物理主机验收这一要求, 继续开展后续工作"). No physical-host run was performed or claimed. Keep deployment instructions as an optional operator resource.
- AC6: Local HTTP fixture proves real adapter path; optional live smoke is opt-in with operator endpoint/key/spending approval and secret-free output.

## Out of Scope

All parent exclusions apply. This child owns only its named seam; no unrelated
scaffold/UI/provider/runtime refactor. Parent criteria referenced above remain
authoritative even when local AC numbering differs.
