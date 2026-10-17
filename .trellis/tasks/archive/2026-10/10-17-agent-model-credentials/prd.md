# Agent-owned Model Configuration and Extensible Providers

## Goal

Let users configure a model provider when creating an Agent, including plaintext
credentials and provider-specific parameters. Model calls remain distributable
Operations, with results returned to authority. Implement the OpenAI-compatible
API first while allowing future providers with different authentication,
configuration, request encoding and response decoding.

## Background and Approval

Task creation is approved ("创建"); implementation is approved ("批准"). Source baseline:
dev18137b1. The user subsequently clarified that a top-level Agent api_key is
too narrow: provider parameters and wire formats may differ completely. This
supersedes the prior key-only draft, which was not approved for implementation.
The user then accepted the recommendation ("同意你的建议"): one active model
binding per Agent in this release, with different bindings across Agents and an
extensible provider interface. There is no model selection/switching API in scope.

Source anchors:
- Agent option validation: apps/beamlet_agent/lib/beamlet/agent/server.ex:85.
- Agent invokes OpenAI request validation and reply normalization directly:
  server.ex:212 and627.
- Integration.Handler invokes OpenAI request validation: integration/handler.ex:28.
- Generic Catalogue.batch parses OpenAI function-call envelopes and JSON strings:
  apps/beamlet_harness/lib/beamlet/harness/catalogue.ex:33.
- Deterministic model depends on OpenAI normalization:
  apps/beamlet_harness/lib/beamlet/harness/models/deterministic.ex:5.
- Actions rejects credential names: apps/beamlet_actions/lib/beamlet/actions.ex:3.
- HTTP provider and Node readiness read executor key_env:
  models/open_ai_compatible.ex:23 and node/provider.ex:20.

## Requirements

- R1: Represent provider identity, provider-specific configuration, credentials
  and execution placement separately. Do not hard-code api_key as an Agent-wide
  option or impose OpenAI configuration requirements on all future providers.
- R2: Keep selected model/provider configuration and credentials in authority
  memory. Carry the selected invocation configuration and credentials with each
  model Operation, without executor-installed user credentials or global caches.
  Executor registrations identify available provider implementations; Tool
  environment/workspace configuration remains executor-local.
- R3: Give Agent a provider-neutral model request/reply/history contract. Provider
  adapters own request construction, authentication, wire response parsing and
  conversion to the neutral contract. Generic Agent, Tool catalogue and executor
  glue must not invoke OpenAI-specific parsers.
- R4: Implement only the OpenAI-compatible nonstreaming text/function-tool subset
  as a real external provider. Preserve transport/TLS/no-retry/size behavior.
  Other provider implementations, streaming, multimodal and automatic fallback
  are out of scope. Extension must be verifiable with a small test provider
  whose configuration/authentication and internal response representation differ.
- R5: Preserve Actions/Runtime generic dependency directions, complete envelope
  bounds, placement, gateway admission, public guarded submit, progress,
  cancellation, lifecycle retirement and single-attempt/no-replay behavior.
- R6: Keep credentials separate from application-generated conversation, Tool
  inputs, snapshots, progress, results and diagnostics. Children receive model
  bindings only via explicit creation options; peer messages do not inherit them.
  No credential service, encryption subsystem or authorization framework is needed.
- R7: Retain ephemeral trusted-cluster operation. No persistence, recovery or
  secure memory erasure promise. Transient BEAM copies may exist until ordinary
  process/message/operation cleanup.
- R8: Migrate creation options, provider registrations, direct Harness calls,
  fixtures, examples and specs together. Replace key_env with explicit invocation
  credentials and remove environment fallback. Preserve historical archived evidence.
- R9: Each Agent has exactly one immutable active model binding for its lifetime.
  Different Agents can use different models/providers/endpoints/credentials.
  Reserve extensibility through the binding/provider interface; no model list,
  switching API or automatic selection is implemented in this release.

## Acceptance Criteria

- AC1 (R1,R2,R4): A remotely created Agent using supplied OpenAI configuration
  and credentials completes model -> workspace Tool -> model and a later turn,
  on an executor with no provisioned user key.
- AC2 (R1,R2,R6): Two Agents with different model bindings/keys use the same
  executor without cross-contamination. Provider-specific validation is exercised;
  unknown provider IDs fail explicitly and never select arbitrary modules.
- AC3 (R3,R4): Agent and generic Harness code have no dependency on OpenAI wire
  parsing. A test-only alternative provider completes the same neutral text/Tool
  path with different configuration/credential fields and no OpenAI envelopes.
- AC4 (R3): Neutral history preserves supported assistant text, complete Tool
  call IDs and order, and Tool observations. Whole batches validate before
  dispatch; malformed replies/history fail; unsupported semantics are explicit.
- AC5 (R5): New invocation data counts toward protocol/deployment caps. Ordinary
  payload/metadata validation stays intact. Existing credential-free handlers,
  lifecycle, role composition, concurrency and failure regressions pass.
- AC6 (R4,R6): OpenAI local TCP/TLS tests retain wire/auth/body/no-retry/redirect/
  overflow assertions. Known fixture credentials are absent from normal generated
  projections and Tool contexts. No implicit child/peer credential inheritance.
- AC7 (R7,R8): Copied backend release checks and current deployment examples
  reflect the migration; Web regressions remain intact. Exact executed checks,
  skipped coverage and limitations are reported.
- AC8 (R9): An Agent's binding remains fixed across model steps and turns. Named
  model collections or switching options are rejected as unsupported creation
  fields. Independent Agents can use distinct configurations of the same adapter.

## Out of Scope

Real non-OpenAI providers, full arbitrary-provider feature parity, automatic
model routing/fallback, hot switching policy, streaming, multimodal, new Tool
capabilities, persistence, credential management products, new dependencies,
physical-host acceptance and paid/live model calls.

## Planning Disposition

Product decisions are resolved. The user approved the single-binding first
release; design.md specifies concrete neutral/provider/invocation contracts and
implement.md records gates and validation. This converged PRD supersedes prior
key-only and multi-binding proposals. The user approved the complete final summary
("批准"), including the compatibility migration. Task activation and implementation
are authorized. No source tests or external calls were performed during planning.
