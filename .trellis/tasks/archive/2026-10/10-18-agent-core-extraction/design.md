# Agent Core extraction design

## Boundary and dependencies

Create beamlet_agent_core with Beamlet.Agent.Core.* modules and no Application callback. Agent depends on Core. Core may use Harness's existing pure Model/Catalogue/Context validators and Jason; it must not invoke providers. Harness currently brings Req transitively: purity is a call/behavior guarantee, not a zero-HTTP-library dependency closure. Do not split Harness in this task.

Core must not depend on Agent, Storage, Runtime or Ecto. No Repo/reader callbacks, clocks, random identity generation, credentials or live refs are passed into Core.

## Modules

- Core.Reducer: existing reference-only state, new/reduce/replay/version, Agent event semantics including inheritance, fork provenance, risk and continuation rules.
- Core.Context: deterministic message/material conversion, complete tool pairing, reply and observation conversion, bounded context, source/policy assembly.
- Core.Decision: small functions for existing reply continuation and restore/resume classifications. It returns data/decisions, never dispatches or commits. Avoid speculative Plan/Effect framework.
- Agent.Reducer: retain current callable surface as storage envelope adapter. Validate canonical data, schema envelope and digest with current Storage.Codec, then invoke Core. Normalize explicitly required digest data for input references; do not persist adapter-only fields.
- Agent.ContextBuilder (and a local context loader if useful): preserve current surface, load and verify sources via Loader/History/Inheritance, then call Core.Context with ordered source-bound materials.
- Agent.Loader/Durable/Server/Integration.Caller: preserve repository access, resource fencing, optimistic concurrency, command reconciliation, fixed operation preparation, registry/lifecycle and Runtime execution.

Exact internal function names may follow existing conventions. Do not expose a large cluster of helpers merely to create modules.

## Event contract

Separate storage-envelope validation from Agent semantic validation without weakening either. Core still checks supported event versions, Agent identity, sequence, payload/turn/step/ordinal linkage, pause and continuation rules. Do not accept arbitrary event names just because they are strings. Adapter validates persisted payload shape/limits/UUID behavior using existing code; Core independently rejects malformed normalized input with safe errors.

Do not copy Storage.Codec's canonical encoder or substitute a regex for Ecto UUID semantics without compatibility evidence. The adapter calculates the existing canonical input digest and passes it as explicit transient normalized data. Existing persisted events and checkpoints retain their bytes/versions/state keys and snapshot interpretation.

## Context contract

Material entry associates an exact timeline source with loaded input or operation data. Loader verifies database existence, ownership, canonical digest, accepted/prepared linkage, inherited closure and read budgets. Core verifies material membership/order/completeness and relevant operation identity, then performs existing message conversion and neutral validation.

Keep inherited_input/inherited_result handling; inherited results preserve original ownership and source resolution. Retain historical catalogue use for stored model reply validation and current catalogue validation at the same existing points. Preserve complete_boundary behavior, including its deliberate avoidance of revalidating old tool arguments against a newer catalogue.

Core may receive full data during a call; long-lived reducer state remains reference-only. Prepared operations are reused exactly, never rebuilt with a new policy/configuration on recovery.

## Decisions and execution

Extract observed pure decisions rather than redesigning the loop. Core classifies normalized replies and continuation positions. Agent still establishes external facts (accepted result integrity, previous owner DOWN, attempt uncertainty, version/generation) before acting. A pure decision does not prove those external facts.

Preflight applies candidate events to a temporary projection. Commit is guarded by existing transaction/CAS rules. Formal state changes only by replaying committed returned events; dispatch only follows successful prepare. Preserve existing command_outcome_unknown reconciliation and execution uncertainty semantics.

## Compatibility and rollout

Keep Agent public APIs and internal facades consumed by Loader/History/TraceVerifier intact where practical. No database migration, event version bump, renamed stored keys or new recovery behavior. Add Core to child dependencies and root backend_apps; let Mix resolve release closure.

Migrate reducer, then context, then small decisions. Validate each before continuing; no parallel writers in one worktree. On failure restore only the current task's identified edits, not unrelated work. Do not reset/checkout shared cwd.

## Risks

- Current dev includes completed durable references that earlier dialogue examples predated.
- Moving validation can change error precedence or allow malformed history; preserve fixtures and regression assertions.
- Context extraction can lose headers/clauses or inherited cases; read generated files completely and compile before broad tests.
- Existing Server has both memory and durable paths; no claim that all process state becomes Core state in this extraction.
