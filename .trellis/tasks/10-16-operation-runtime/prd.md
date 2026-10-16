# Operation Contracts and Multi-node Runtime

## Goal

Make generic structured Operations execute on eligible connected BEAM nodes without Agent, Harness or Phoenix.

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
This child is planning only. The parent final summary must be approved before
activation; no product code or implementation dispatch is authorized yet.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies

No child dependency. This is the first implementation target after parent-plan approval.

## Requirements

1. Own parent R1–R3/R7 runtime portions and AC1/AC3/AC4/AC9. Provide typed Operation/Execution/Result/live-ref contracts and validated data-only descriptions.
2. Implement explicit endpoint discovery/freshness, capability/environment/node filtering, deterministic placement and executor-local multi-pool admission.
3. Provide asynchronous submit/status/cancel, deadlines, bounded progress/retention, correlated one-attempt lifecycle and coordinator acceptance of at most one Result.
4. Own temporary supervised workers/coordinators and loss cleanup; infrastructure restart must not replay business work or leave unaccounted workers.

## Acceptance Criteria

- AC1: A non-AI handler runs remotely between independent VMs with no Agent/Harness/Phoenix dependency; no eligible target yields a coordinator Result without an invented Execution.
- AC2: Concurrent admissions obey local pools; stale reports/wrong capability/environment/endpoint incarnations are rejected and never cause fallback/retry.
- AC3: Tests distinguish cancellation request/observed shutdown, completion races, deadline, owner/coordinator/gateway failure, uncertain admission and partition; late/duplicate messages never overwrite accepted results.
- AC4: Progress/count/payload/coordinator/retention limits hold; expired refs are unavailable and every test peer is cleaned up.

## Out of Scope

All parent exclusions apply. This child owns only its named seam; no unrelated
scaffold/UI/provider/runtime refactor. Parent criteria referenced above remain
authoritative even when local AC numbering differs.
