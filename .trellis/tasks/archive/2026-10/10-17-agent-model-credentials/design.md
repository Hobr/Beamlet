# Agent-owned Model Configuration and Extensible Providers — Design

## Status and Boundary

Approved for implementation ("批准") after final planning review. The user selected
one active model binding per Agent ("同意你的建议"). No product decision remains open.
This design supersedes top-level Agent api_key, executor-owned endpoint/model
configuration, flat string-only credentials and OpenAI-shaped generic history.

Deliver one end-to-end change: user-supplied model binding -> generic distributed
Operation -> selected local provider adapter -> neutral reply -> Agent loop.
Keep existing Tool locality, placement policy, public admission and lifecycle.
One task is appropriate because neutral contracts and credential transfer are
prerequisites for the same externally verifiable flow.

## Model Binding

Agent.start(authority, id: ..., model: binding, tools: ..., catalogue: ...) accepts
one required binding, immutable across turns for the Agent lifetime:

```elixir
%{
  provider: "openai-compatible",
  config: %{"model" => "configured-model", "base_url" => "https://example.test/v1"},
  credentials: %{"api_key" => user_supplied_key},
  placement: %{claims: %{"requests" => 1}}
}
```

Exactly provider/config/credentials/placement are accepted; credentials and
placement may be omitted and default to %{}. Config is a string-key JSON object.
Provider ID matches [a-zA-Z0-9_-]{1,64}. Placement accepts only environment,
allowed_nodes and claims with current Operation validation and bounds; absent
fields preserve current defaults. There is no caller-selected executable module,
global api_key, model collection, automatic provider fallback or switching API.

Model config/credentials stay in private Agent state, never catalogue/routes or
snapshot projections. Explicit child creation supplies its own model binding;
no inheritance. Peer payloads do not acquire model configuration automatically.

## Provider Interface and Local Registration

Harness.Model is a behaviour with two required callbacks:

```elixir
validate_invocation(%{config: config, credentials: credentials})
# => :ok | {:error, safe_atom}

complete(%{messages: messages, catalogue: catalogue},
         %{config: config, credentials: credentials},
         %Beamlet.Harness.Context{})
# => {:ok, %{kind: :text | :tool_calls, content: text_or_nil, calls: calls}}
#  | {:error, safe_atom}
```

Validation is pure and performs no HTTP/file IO. Common validators own neutral
request/reply/binding data and byte bounds; adapters own provider-specific fields.
Agent validates before creation; executor revalidates invocation before use.
complete also validates for direct Harness consumers. Failures use safe errors,
not raw config/credentials or callback exception messages.

Node gains trusted model_providers: %{"provider-id" => Module}, max32 entries.
Defaults register OpenAICompatible and Deterministic with stable IDs
"openai-compatible" and "deterministic". Registered modules are locally configured,
loaded, and must export the two callbacks. Never atomize portable IDs. Model
availability is separate from existing providers (monitored PIDs).

AuthoritySupervisor receives this trusted registry at startup (standalone default
is the same built-in map). Store it as local Registry metadata or equivalent
authority-owned immutable configuration; Agent does not depend on Node code.
Executor Handler receives its own validated registry in local settings.
Node must not pass user credentials into either registry or Directory reports.

Node profiles/routes continue to configure Tools. Old type:model static profiles
are rejected with invalid_node_configuration, and examples migrate to registry
plus Agent binding. Existing Tool profile/workspace settings remain local.

Each executor advertises capability "model.provider:" followed by the ID for each registered
adapter; model Operations require the derived capability. Check union of Tool
and model capabilities against existing Runtime report/count limits. Placement
can further restrict execution; a chosen node never substitutes another provider.

## Neutral Request, Reply and History

Use Harness-owned validation, independent of OpenAICompatible. Native request:
%{messages: list, catalogue: map}; exactly those keys.

Canonical messages use string keys:
- system/user/assistant text: %{"role" => role, "content" => text};
- assistant Tool batch: %{"role" => "assistant", "content" => text_or_nil,
  "calls" => [%{"id" => id, "name" => name, "arguments" => decoded_object}]};
- Tool observation: %{"role" => "tool", "call_id" => id, "content" => text}.

Replies have exactly kind/content/calls. Text reply requires binary content and
empty calls; Tool reply permits binary/nil content and requires1..8 complete calls.
No raw provider assistant message or OpenAI wrapper is part of the neutral reply.
Agent constructs canonical assistant history from the validated reply.

Catalogue.batch validates canonical calls/decoded arguments atomically. OpenAI
JSON argument parsing moves into its adapter. Preserve supported catalogue schema,
unique nonempty IDs (max128 UTF-8 bytes), original order and full-batch checks.
History requires one observation per pending call in original order before the
next model message. Preserve128-message/1MiB context bounds,1MiB native request/
reply bounds,16KiB call arguments,8-call batches,16 model steps and snapshot limits.
Unsupported message/reply fields or semantics fail explicitly.

Agent.Server, Integration.Handler, Catalogue and Deterministic must not call
OpenAI parsers or reconstruct OpenAI envelopes. A small test adapter with different
configuration/authentication fields and internal reply data proves this seam.
Generic validators can be extracted into cohesive Harness modules; do not add a
plugin framework or multiple forwarding-only wrappers.

## OpenAI-Compatible Adapter

Config accepts required string keys base_url/model and optional timeout_ms
(default5000,1..60000) and allow_local_http (defaultfalse). Credentials accepts
exactly api_key, UTF-8 binary1..4096 bytes without CR/LF. Reject key_env and unknown
fields, no executor environment fallback. Other adapters define their own shapes.

The adapter converts canonical messages/calls/catalogue to OpenAI messages/function
tools (including encoding argument objects and mapping call_id to tool_call_id).
It owns choices/finish_reason parsing, response normalization and malformed/
refusal/incomplete-result errors. Preserve supported text/function semantics,
single-choice nonstreaming behavior, no retries/redirects, verified TLS, fresh Req
steps, safe errors and all-status size/encoding handling. No new generation
parameters, streaming, multimodal or other external protocol is implemented.

Deterministic config migrates to neutral reply fixture data, credentials default
empty; it validates via common Harness code rather than OpenAI normalization.

## Generic Operation Credentials and Runtime Transfer

Add Operation.credentials default %{}. It is a plain string-key JSON object;
nested objects/lists/scalars are allowed. Bound top-level entries at32, field
names at128 UTF-8 bytes, depth at24 and the complete serialized credential map
at16384 bytes. JSON data means valid UTF-8 strings, numbers, booleans, nil, proper
lists and plain string-key maps; no executable values, PIDs, refs, ports, tuples,
arbitrary atoms or structs. Root/workspace_root keys remain rejected. Credential
names such as api_key/token/credentials are allowed only in this dedicated field.

Actions validates this field separately and validates the other Operation fields
with existing ordinary data policy. Include credentials in the full262144-byte
protocol ceiling and current deployment cap at both public submit and gateway.
Config is capped at16KiB serialized JSON and validated as ordinary data; nested
provider-specific authentication belongs in credentials, not config.

Caller constructs a model payload identifying invocation type/provider/config/
neutral request, requires derived provider capability and attaches credentials.
Tool payloads retain profile/request, have no model invocation values and carry
empty credentials. Handler discriminates the two forms without inspecting secrets
in ordinary payloads. Runtime Worker forwards context.credentials unchanged along
with current local settings/remaining_ms/progress/cancelled? fields.

Use existing OperationOwner and public Runtime.submit(require_live_owner:true).
Runtime contains no provider-specific parsing/dispatch or model dependencies.
Neither provider config nor credentials are copied into progress/status/Results.
Local executor settings and registry are immutable across concurrent invocations.

## Migration, Lifetime and Rollback

This is an intentional migration of model creation/direct Harness settings and
model Node profiles. Old key_env, top-level Agent api_key and old model-route-only
options fail explicitly. Update current fixtures/examples/scripts/specs together.
Generic credential-free Operations and Tool registration remain compatible.
Deploy matching builds; mixed-version execution is unsupported.

User configuration/credentials can exist as plaintext in authority/execution
processes and transient messages until normal cleanup/retention. There is no
persistence, credential cache, secure erasure or protection from administrator
inspection. Output absence tests cover generated fields, not malicious providers
echoing secrets. No paid calls or physical hosts are needed.

Expected changes: Harness behaviour/neutral validators/Catalogue/adapters; Agent
creation/loop/authority registry/integration; Node registry/readiness/role wiring;
Actions Operation and Runtime worker forwarding; adjacent tests and fixtures;
current deployment examples and executable specs. No lock/dependency change.
Do not rewrite archived historical reports. Roll back matching source/examples/
specs as one build if acceptance fails; no retry or unrelated reset workaround.
