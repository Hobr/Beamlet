# Provider Abstraction Inspection

Revised planning evidence at source18137b1. User requires OpenAI API implementation
first, but provider-specific configuration/authentication and genuinely different
request/response protocols must fit the interface later.

## Observed Coupling

- Harness.Model.complete/3 is already a behaviour, but its map contract has no
  independent neutral validation implementation.
- Agent.Server aliases OpenAICompatible, validates messages with its
  validate_request/1, and reconstructs choices/finish_reason/message to compare
  normalized replies (server.ex:212,627). These are concrete-provider decisions
  in the orchestration implementation.
- Agent Integration.Handler also calls OpenAI validate_request before invoking
  any registered model (integration/handler.ex:28).
- Catalogue.batch accepts OpenAI type/function wrappers and JSON argument strings,
  and decodes those strings itself (catalogue.ex:33). Separate wire decode from
  neutral ID/name/decoded-arguments batch validation.
- Deterministic.complete uses OpenAI request validation and normalization
  (models/deterministic.ex:5). It does not currently prove protocol independence.
- Node.Provider recognizes the concrete OpenAI module and checks endpoint/model/
  key_env directly; provider-specific validation should be owned by the adapter.

## Implication

A provider field alone does not create a useful extension seam. Neutral history,
request/reply and catalogue batch contracts must be independent of any external
wire codec. OpenAI owns encoding/decoding and credential requirements. Agent
owns turns/joins, Node owns implementation availability, Runtime owns generic
admission/transport/lifecycle.

Use a small test provider with different config/credentials/internal reply data
to exercise the same neutral flow. This is a protocol-independence regression,
not a second production network provider or a new plugin framework.

## Planning Precedence

Current prd.md/design.md supersede the key-only proposal in credential-flow.md.
They specify Agent-owned provider configuration and structured credentials rather
than a top-level api_key and static executor endpoint/model settings. The user
accepted one immutable active binding per Agent ("同意你的建议"). design.md now
specifies the neutral and provider contracts and exact invocation bounds. Final
planning review approval remains required before activation or implementation.
