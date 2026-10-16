# Operation Contracts and Multi-node Runtime — Design

## Shared Contract and Review Status

Parent requirements and cross-child acceptance: `../10-16-distributed-agent-mvp/prd.md`.
Parent technical design and operational limits: `../10-16-distributed-agent-mvp/design.md`.
The user approved the complete parent/child plan on 2026-10-16 ("批准").
Implementation is authorized once this child's prerequisite gates pass; only the
currently activated child is an implementation target.
A material contract/scope change returns to parent review. No persistence,
distributed consistency, automatic replay, Web UI or sandbox scope expansion.

## Dependencies and Ordering

No child dependency. This is the first implementation target after parent-plan approval.

## Owned Design

Implement parent design §§2–4. Public namespace stays Beamlet.Actions/Beamlet.Runtime.
Suggested module groups: Actions structs/validation/Handler; Runtime facade,
SharedSupervisor, Directory, NodeEndpoint, OperationCoordinator,
ExecutionSupervisor, ExecutorGateway and Worker. Use small ownership-focused
modules; avoid a second generic forwarding layer.

Descriptions carry data; context resolves local handler resources. Gateway owns
task handles/capacity. Coordinator owns result acceptance and deadline. Allocate
attempt identity before admission; no admitted handle before worker admission.
Use MFA Task.Supervisor workers and temporary business children. Endpoint/gateway
incarnation checks and bounded attempt tracking prevent duplicate admission.

Support startup options/child_specs independent of product Node composition.
Reports never contain provider secrets/live clients. Resource/capability semantics
are opaque, not Tool or LLM logic. Parent default limits are configurable validated
options; overruns are explicit and serialized envelopes count toward size bounds.

## Role Composition Decision (2026-10-16)

The parent confirmed that execution is opt-in: `execution: false` is the default
for a convenience runtime composition entry; `execution: true` starts the coupled
Task.Supervisor/Gateway subtree. Shared-only nodes must start neither process,
even when the handler table would be empty. Keep ExecutionSupervisor an owned
subtree with a usable child specification for Node composition; a convenience
shared entry may wire it without merging execution accounting ownership.

NodeEndpoint remains discoverable on every role, including authority/interaction.
Execution readiness and capabilities are advertised only with explicit execution
activation and a live ready gateway/providers. An absent gateway is a normal
shared-only configuration; gateway loss withdraws readiness and invalidates affected
work. Add shared-only/executor/combined startup coverage and document exact options
in the downstream handoff. This refines the approved role boundary, not task scope.

## Consumer Handoff

Record actual struct fields/constructors, Handler callbacks, submit/event/control
shapes, child_spec options, limits and failure reasons. Child 3 depends on these.
Any parent design deviation must be explained and reviewed before consumers adopt it.

## Compatibility and Rollback

Replace generated stubs only within this child. No stable domain API exists yet;
preserve unrelated Web behavior. Deploy matching builds to peers. On failed gate,
stop and revise scoped changes; no reset of unrelated work or automatic business
replay. Record actual checks and limitations for the next child.
