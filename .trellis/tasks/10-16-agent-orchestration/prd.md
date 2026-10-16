# Agent Orchestration and Node Role Composition

## Goal

Run responsive Agents with parallel Tool Operations, Sub-agent/peer collaboration and explicit role/provider activation.

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies

Prerequisite gate satisfied on 2026-10-16: parent accepted child 1 and child 2
implementation/check evidence and their actual handoffs. Consume
`../10-16-operation-runtime/handoff.md` and `../10-16-harness-providers/handoff.md`
plus linked executable specs. Commit/archive bookkeeping is deferred to final
delivery; no speculative or weakened upstream contracts are authorized.

## Requirements

1. Own parent R2/R4–R7 Agent/Node portions and AC3/AC6–AC10. Preserve generic-runtime/Harness independence through isolated integration adapters.
2. Provide explicit-authority live AgentRef, local identity uniqueness, temporary Agent lifecycle, bounded context and asynchronous model/parallel-tool loop.
3. Provide same-channel ordered snapshots/events, bounded subscriber credits/coalescing and stop-before-follow-on behavior.
4. Implement API-driven correlated delegation and peers, responsive joins, child stop ownership, independent peer lifetime and late-reply isolation.
5. Compose shared/authority/execution/provider trees by declared roles. Readiness follows actual live providers; executor-only nodes load adapters without starting Agents.

## Acceptance Criteria

- AC1: Three-node fake-model/workspace loop returns final answer from authority with executor-side operations; wrong workspace/model profiles do not place or fall back.
- AC2: Whole Tool batch validates before any dispatch. Independent calls finish out of order and join by original call ID/order; concurrent Agents progress within limits.
- AC3: Parallel child turns run through Runtime while parent holds zero execution slots, remain stoppable, report child loss, and ignore stale replies; peer request/reply does not couple lifetimes.
- AC4: Snapshot is first on the same subscriber channel; bounded slow/disconnected subscribers neither block nor terminate Agent.
- AC5: Authority registry loss invalidates old Agents/refs; provider/gateway loss withdraws readiness/affected work without automatic replay; all role combinations and local gateway path are tested.

## Out of Scope

All parent exclusions apply. This child owns only its named seam; no unrelated
scaffold/UI/provider/runtime refactor. Parent criteria referenced above remain
authoritative even when local AC numbering differs.
