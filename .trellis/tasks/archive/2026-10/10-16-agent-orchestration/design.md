# Agent Orchestration and Node Role Composition — Design

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies and Ordering

Prerequisite gate satisfied on 2026-10-16: parent accepted child 1 and child 2
implementation/check evidence and their actual handoffs. Consume
`../10-16-operation-runtime/handoff.md` and `../10-16-harness-providers/handoff.md`
plus linked executable specs. Commit/archive bookkeeping is deferred to final
delivery; no speculative or weakened upstream contracts are authorized.

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

## Parent-owned public Runtime admission repair

Parent reviewed the independent seam proposal and authorizes this narrow owning-seam
repair under the approved R1/R3/R7 contracts. Runtime owns all admission validation,
current Directory byte caps, ID/ref/spec allocation and error normalization. Add an
optional public `require_live_owner: true` submit mode for local owner PIDs; preserve
default API compatibility. The Runtime-owned start/init/dispatch boundary must
reject dead ownership after delayed supervisor or Directory admission, monitor
before dispatch, and never retry. Agent OperationOwner calls public submit and
removes its private coordinator construction. This is a single admission seam
repair across producer and consumer, not an architecture or scope expansion.

Runtime must retain no Agent/Harness dependency. Checks cover malformed Operations,
current reduced byte cap/unavailable Directory, capacity/errors, dead owner before
and during blocked admission, actual DOWN before resume, and no late execution.
Only Runtime facade/coordinator plus focused tests and Agent OperationOwner plus
focused Agent/Node regressions are authorized product edits for this pass.
Independent recheck remains required before child 4. Parent owns spec sync.

## Consumer Handoff

Document lifecycle/command/event/credit protocols, role config/provider registration
and boot options for child 4. Child 4 may wrap these interfaces; it must not duplicate
Agent loop or role ownership.

## Compatibility and Rollback

Replace generated stubs only within this child. No stable domain API exists yet;
preserve unrelated Web behavior. Deploy matching builds to peers. On failed gate,
stop and revise scoped changes; no reset of unrelated work or automatic business
replay. Record actual checks and limitations for the next child.
