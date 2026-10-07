# Capability Composition and Execution Path

Status: reviewed target contract. It does not promise full Cordis API compatibility.

## 1. Scope / Trigger

Own Scope visibility/configuration/lifecycle, provider compatibility, immutable capture, live resource matching and the external creation-to-execution seam.

## 2. Signatures

~~~text
CapabilityFacade.call(arguments, reply_key) -> Invocation
Scope.describe(scope_ref) -> versioned_descriptor
Scope.resolve(descriptor, operation_ref, constraints) -> eligible_binding | unavailable
Effect.invoke(binding, intent, execution_context) -> observation
ExecutionController.dispatch(effect_ref, orchestration_permission) -> admission_result
~~~

Interfaces use portable descriptors and registered local code. An execution context can contain live provider-local handles; it is never persisted or placed in an archive.

## 3. Contracts

| Data | Fields / constraints |
|---|---|
| ScopeDescriptor | scope_id/version, logical parent/isolation refs, bindings/configuration, execution-controller reference |
| OperationRef | capability name, operation name, contract version; registered declarations |
| OperationDeclaration | argument/reply schema refs, repeatability/retry conditions, resource requirements |
| ProviderBinding | provider/resource logical identities, node/generation, supported contract/code version, deduplication domain if applicable |
| ExecutionContext | opaque stable request token, reply/invocation correlation, local resource access; no public durable-store object |
| Intent capture | normalized arguments, effective configuration, Scope meaning, resource constraints, saved retry declaration |

Providers can appear, disappear, be replaced or be unloaded. Declared service dependencies determine availability; scope ownership controls live resource cleanup. Dependency restart/disposal rules must be declared per provider rather than inferred from an Agent concept.

Persist descriptors, not service objects, callbacks, PIDs, ports or credentials. Reconstruct live resources locally. Changing configuration later does not reinterpret an existing Effect.

Resolve a compatible live implementation at attempt time. An operation-name match or equal local filesystem path is insufficient resource/semantic identity. Registered declarations assert compatibility; the runtime is not an equivalence prover.

Worker preflight checks the admitted provider generation and resource constraints before invocation. A changed generation requires a new resolution/admission rather than silent substitution inside the same attempt. A proven pre-invocation rejection can establish non-execution; later loss is uncertain.

### External Execution Controller

1. Effect creation commits pending intent.
2. The configured controller coordinates readiness/review and resolves a provider.
3. It requests the normal authoritative admission.
4. A worker invokes and records the observation.

The default controller is automatic. Replacing it for a scoped path disables the automatic bypass for that path. Every controller remains subject to active mode, current orchestration permission, immutable intent, provider eligibility and retry constraints.

External review owns its UI, durable decisions and waiting semantics. Effect/Durable has no awaiting_approval state, approve/reject decision API or Agent-specific workflow. A passive event observer cannot establish a pre-execution gate.

Changes to a controller or suspension do not retroactively revoke an already granted attempt. This is ordinary scoped composition, not a new middleware DSL.

Resource/private configuration belongs to providers. Export carries logical requirements; target resource permissions/availability can prevent execution without rewriting intent. Registration cleanup is not external compensation.

## 4. Validation & Error Matrix

| Condition | Behavior |
|---|---|
| Dependency/provider unavailable | No eligible binding; pending/unavailable projection, no fabricated result |
| Same name but incompatible contract/schema/resource | Reject binding |
| Provider generation changes after admission | Preflight rejects if operation has not started; otherwise retain uncertainty |
| Scope settings changed after creation | Stored arguments/effective configuration unchanged |
| Retry selects a new deduplication domain | No automatic retry unless independently justified explicit repeat permission exists |
| External controller installed alongside bypassing automatic path | Configuration/contract violation |
| Archive/configuration supplies arbitrary executable callbacks | Reject at trusted registered-code boundary |
| Scope marked as hostile-code sandbox | Invalid architecture claim |

## 5. Good / Base / Bad Cases

Good: queued model X/effort Y intent executes on a replacement provider that still satisfies X/Y and its saved resource/operation contract.

Base: one scoped provider, no dynamic change, using the same descriptor/admission path.

Bad: reroute to current model Z simply because the old provider disappeared, reuse a request key in another provider account, or let an event listener race automatic execution.

## 6. Tests Required

<a id="s9"></a>
### S9 — Scope and Provider Lifecycle

Assert distinct scopes can isolate/select implementations, dependencies block readiness, unloading cleans live registrations, and pending/running work receives the defined unavailable/unknown outcome without undo claims.

<a id="s12"></a>
### S12 — Immutable Capture and Replacement

Create an intent, change Scope configuration and provider generation, then execute. Assert saved arguments/configuration, compatible matching, explicit absence behavior and worker preflight. A deduplicated retry cannot silently cross realms/expired retention.

<a id="s14"></a>
### S14 — Historical Inspection and External Gate

Inspect state, requests/results, attempts and branch differences through projections. Install an external controller: persist an Effect, withhold its dispatch externally, and assert the automatic path cannot execute it. Release via the normal admission API. Assert Durable schemas contain no approval-specific state or decision workflow.

## 7. Wrong vs Correct

~~~text
Wrong: listen to effect_created while default dispatch already runs.
Correct: configure the external controller as the execution path before authoritative admission.

Wrong: persist ctx/provider PID and use it after restart.
Correct: persist a logical Scope/resource descriptor and resolve a valid live generation.

Wrong: replace the stored request with current Scope settings.
Correct: keep intent immutable and choose only a compatible current binding.
~~~
