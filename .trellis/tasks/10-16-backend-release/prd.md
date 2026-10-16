# Backend CLI, Release and Multi-machine Acceptance

## Goal

Deliver usable IEx/CLI entry points and a backend release, with reproducible automated and physical multi-machine acceptance.

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
This child is planning only. The parent final summary must be approved before
activation; no product code or implementation dispatch is authorized yet.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies

BLOCKED until children 1–3 pass their gates and publish actual interfaces. Parent owns final cross-child AC sign-off and remains incomplete without required physical-host evidence.

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
- AC5: A repeatable physical-host run records B and C on distinct physical machines, remote marker-file operation, role/identity assertions and stop/loss behavior. No host access means explicit pending acceptance, not success.
- AC6: Local HTTP fixture proves real adapter path; optional live smoke is opt-in with operator endpoint/key/spending approval and secret-free output.

## Out of Scope

All parent exclusions apply. This child owns only its named seam; no unrelated
scaffold/UI/provider/runtime refactor. Parent criteria referenced above remain
authoritative even when local AC numbering differs.
