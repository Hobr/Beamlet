# Beamlet Domain

Canonical language for the generic runtime and its consumers. Implementation choices belong in the design and specifications.

## Language

**Computation Definition**:
The versioned rules for advancing application state in response to inputs.
_Avoid_: Agent definition, process image.

**Run**:
One occurrence of a computation definition, with its own identity, state, and history.
_Avoid_: PID, session when referring to the generic runtime.

**Invocation**:
An application-level request for a capability operation, with arguments and a reply key.
_Avoid_: Effect when referring to the business-facing request.

**Effect**:
One logical operation whose immutable intent is persisted and whose execution and outcome are tracked.
_Avoid_: Attempt, Cordis registration effect, Ra scheduling effect.

**Attempt**:
A distinct permission to a provider to execute an Effect, with its own observed outcome.
_Avoid_: Effect when referring to one retry or execution grant.

**Outcome**:
An observation or explicit resolution concerning operation completion. Unknown does not establish non-execution.
_Avoid_: Failure when the execution outcome is unknown.

**Capability**:
A stable operation contract available within a Scope.
_Avoid_: Node, concrete Provider.

**Provider**:
An implementation of capability operations with access to their required resources.

**Scope**:
A context for capability visibility, selection, configuration, and lifecycle relationships.
_Avoid_: Security sandbox.

**Resource Reference**:
A stable logical resource reference with applicable identity or matching constraints.
_Avoid_: Live resource handle.

**Authority Domain**:
The domain within which a designated authority group determines canonical Run histories.
_Avoid_: BEAM cluster when referring only to storage authorities.

**Storage Authority**:
A user-designated node participating in authoritative persistence.

**Computation Host**:
A node assigned to advance a Run using its definition.

**Execution Node**:
A node that can provide resources and execute capability operations.

**Stable Boundary**:
A committed application-state point at which relevant Effects and their completion delivery are settled.

**History Prefix**:
The history associated with a selected boundary, including completed operation outcomes.

**Branch**:
A Run derived from a stable boundary of another Run, with independent identity for subsequent work.

**Lineage**:
The origin relationships connecting Runs and selected branch boundaries.

**Suspension**:
A durable mode preventing new advancement and execution grants while retaining admitted work's outcomes.
_Avoid_: External cancellation.

**Computation Archive**:
A portable representation of a stable boundary, its data/history, and compatibility requirements.
_Avoid_: Process dump, external-environment snapshot.
