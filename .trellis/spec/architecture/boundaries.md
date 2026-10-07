# Logical Boundaries

Status: reviewed target contract. Physical packages and code remain unimplemented.

## 1. Scope / Trigger

Own the generic/domain boundary and dependency direction. These contracts span computation, storage, capabilities and application surfaces.

## 2. Signatures and Responsibility

| Logical group | Interface responsibility | Allowed dependencies |
|---|---|---|
| Beamlet-core | DefinitionRef, RunRef, Invocation, Reply and portable-data contracts | OTP/Elixir |
| Cordex | Scope descriptors, service selection, provider generations and resource lifecycle | OTP/Elixir; no Agent or durable-computation logic |
| Beamlet-effect | Intent normalization, provider eligibility and one provider invocation | Core and narrow Cordex integration |
| Beamlet-durable | Authority commands, hosts, dispatch/worker protocol, control and archives | Core, Effect, Cordex integration and selected storage |
| Beamlet-lib | Public Beamlet facade and role-aware bootstrap | Generic groups |
| Beamlet-agent | Agent definition, LLM/tool/settings/subagent facades/providers | Public generic contracts |
| Surfaces | Interaction, projections, authenticated adapters, configured host roles | Agent and public generic controls |

The narrow target calls are:

~~~text
Definition.step(state, application_input) -> step_result
CapabilityFacade.call(arguments, reply_key) -> Invocation
Effect.invoke(binding, intent, execution_context) -> observation
Authority.command(domain_ref, envelope) -> result
~~~

Names are interface notation. They do not require an OTP application or process per row. Begin with namespaces; separate applications only for genuine distribution/lifetime/dependency needs.

## 3. Contracts and Data Flow

~~~mermaid
flowchart TD
    A["Application state and Invocation"] --> H["Generic computation host"]
    H --> S["Authoritative state + inbox + Effects"]
    S --> C["Configured controller and Scope resolution"]
    C -->|"conditional admission"| S
    S --> W["Durable worker"]
    W --> E["Effect invocation"]
    E --> P["Local capability provider"]
    P --> W
    W --> S
    S -->|"ordinary capability Reply"| H
~~~

A Durable worker calls Effect invocation and records its observation. Effect invocation does not import Durable. No cyclic result-sink abstraction is required.

Foundation records may contain opaque application data/metadata. They must not define model, effort, conversation, tool, or subagent fields/branches. Those are operation arguments and state in application-owned schemas.

Agent definitions/facades never construct/read Effect or Attempt records. Providers receive ordinary arguments, stable request tokens and local resource context, without a durable-store implementation object.

Cordex owns live services locally. Durable owns logical descriptors, not service objects, PIDs or connections. Cordis registration effects, Ra scheduling effects and Beamlet durable Effects are different concepts.

## 4. Validation & Error Matrix

| Violation | Required boundary behavior |
|---|---|
| Agent definition imports Effect/Durable records | Dependency/contract check fails |
| External input supplies arbitrary module/function/update callback | Reject at registered-code/application boundary |
| Persisted state contains a live handle/closure | invalid_data before acknowledgement |
| Effect executor imports Durable to record results | Move result recording to the Durable worker |
| Missing registered compatible definition/provider | Block execution with explicit compatibility/resource outcome |
| New physical process/app exists only to organize code | Use a module unless a runtime responsibility requires it |

## 5. Good / Base / Bad Cases

Good: the same runtime drives an Agent and an object-processing definition with different operation contracts.

Base: one node performs every role; the same logical interfaces still apply.

Bad: Durable implements special handling for llm.chat or subagent creation, or a facade performs HTTP inside Definition.step.

## 6. Tests Required

<a id="s1"></a>
### S1 — Generic and Agent Boundaries

Dependency/API assertions must show that Agent state transitions depend only on portable state, Invocation and Reply. No generic state machine branches on Agent operation names. Trace UI input through authority, resolution, worker and committed Reply.

<a id="s6"></a>
### S6 — Non-Agent Contract Parity

Run an object-read/digest/content-addressed-write definition using the same state, Effect, admission, outcome and recovery contracts. Move its host between nodes and assert no Agent service/type is required.

## 7. Wrong vs Correct

~~~text
Wrong: Definition.step -> LLM HTTP -> write state afterward.
Correct: Definition.step -> Invocation -> atomic authority commit -> provider execution -> committed Reply.

Wrong: Effect.invoke -> Durable.record_outcome.
Correct: Durable worker -> Effect.invoke -> Durable authority outcome command.
~~~
