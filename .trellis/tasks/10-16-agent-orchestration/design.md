# Agent Orchestration and Node Role Composition — Design

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
This child is planning only. The parent final summary must be approved before
activation; no product code or implementation dispatch is authorized yet.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies and Ordering

BLOCKED until child 1 operation-runtime and child 2 harness-providers pass their gates and publish actual contract handoffs. No broad speculative adapter implementation before both.

## Owned Design

Implement parent design §§4 and 6, consuming actual child 1/2 handoffs.
Suggested groups: Agent facade/Ref/Server/AuthoritySupervisor, Integration
caller/execution handlers; Node configuration/supervisor/provider composition.
Keep HTTP/sandbox internals out of Agent and runtime algorithms out of Node.

Agent state tracks incarnation, active turn generation, context, outstanding
operation→tool IDs, ordered batch, child/delegation maps, peer correlations and
subscriber credits. Synchronous calls are bounded command acceptance only.
All model/Tool/child completion is asynchronous. Busy input/delegation commands
that would mutate an in-flight context reject explicitly.

Delegation API starts a parent group turn or uses a defined compatible waiting
state, starts temporary children on explicitly authority-ready nodes and joins
results before any configured model continuation. It does not add an LLM-facing
delegation Tool. Peer messages are bounded correlated Agent API messages, not
implicit user inputs or durable inboxes. Sender/receiver/turn incarnation checks
and monitors prevent late reply reuse. Stopping first prevents new scheduling.

Node supplies validated role-specific children, allowlisted handler/provider
registrations, opaque profile/environment labels and local capacity pools.
Provider supervision/readiness invalidates affected work on loss. Authority may
inspect descriptors without starting clients or needing executor keys/roots.
Shared Node API must accept trusted configuration usable later by release/CLI.

## Consumer Handoff

Document lifecycle/command/event/credit protocols, role config/provider registration
and boot options for child 4. Child 4 may wrap these interfaces; it must not duplicate
Agent loop or role ownership.

## Compatibility and Rollback

Replace generated stubs only within this child. No stable domain API exists yet;
preserve unrelated Web behavior. Deploy matching builds to peers. On failed gate,
stop and revise scoped changes; no reset of unrelated work or automatic business
replay. Record actual checks and limitations for the next child.
