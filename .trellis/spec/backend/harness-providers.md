# Native Harness and Providers

## Scenario: adapt native model/Tool work into Operations

### 1. Scope / Trigger

Use these contracts when implementing Agent integration or adding providers.
Harness depends on Req/Jason, never Actions/Runtime/Agent/Phoenix. Source:
`apps/beamlet_harness/lib/beamlet/harness/`; no application callback starts roles.
The Agent adapter alone resolves portable profile/environment IDs to local native
modules/settings and translates Runtime hooks. Catalogue construction needs no
credentials, root, provider process or HTTP call on authority.

### 2. Signatures

```elixir
{:ok, catalogue} = Beamlet.Harness.Catalogue.new([tool_module.descriptor()])
request = %{messages: [%{"role" => "user", "content" => "hello"}], catalogue: catalogue}
{:ok, reply} = model_module.complete(request, local_settings, native_context)
{:ok, calls} = Beamlet.Harness.Catalogue.batch(wire_calls, catalogue)
{:ok, value} = tool_module.invoke(call.arguments, local_settings, native_context)
```

Model.complete/3 returns `{:ok, reply_map} | {:error, safe_atom}`. Tool.descriptor/0
returns data; invoke/3 returns `{:ok, map} | {:error, safe_atom}`. OpenAICompatible
and WorkspaceRead also offer /2 with default Context. Native deterministic models
and Tools exercise the same validation/hook boundaries.

### 3. Contracts

Request has exactly `messages` and `catalogue`. Reply:
`%{kind: :text | :tool_calls, content: binary | nil, calls: [call], assistant: map}`.
Call: `%{id: opaque_binary, name: registered_string, arguments: string_key_map}`.
Preserve original call IDs/order and original supported assistant fields. Join
concurrent Tool results by identity then append in original order. Complete batch
validation precedes every dispatch; Catalogue never invokes modules itself.

Catalogue.validate/1 requires keys equal descriptor names. Descriptor has exactly
string keys name/description/parameters. Names match `[a-zA-Z0-9_-]{1,64}`. Supported
schema is a shallow object with properties/required/additionalProperties; primitive
string/integer/number/boolean, typed enum, string minLength/maxLength and numeric
minimum/maximum. String limits count codepoints. Default additionalProperties is
false; explicit true allows extra JSON primitive values with string keys only.
Reject arrays, nested schemas, refs, patterns, unions and unknown keywords.

Context is a local struct with optional progress/1 and cancelled?/0 functions.
Context.append/2 bounds growth without eviction. Model validate_request/1 also
checks canonical catalogue and complete ordered assistant/tool history. A batch
must be followed by one tool observation per ID, in original order, before the
next message/model step. Partial/orphan/out-of-order history is invalid. Hooks
are trusted local code. Cancellation is checked before invocation; cancellation
during blocking IO and overall deadlines belong to Runtime worker lifecycle.
Worker termination does not establish upstream cancellation or absence of billing.
Environment struct has only opaque id; composition validates/resolves that label.

OpenAICompatible local settings: base_url/model/key_env, optional timeout_ms
(default 5000, 1..60000) and allow_local_http (boolean). Reject unknown keys,
including arbitrary Req/TLS overrides and generation parameters. HTTPS requires
peer verification; explicit development HTTP permits only localhost/127.0.0.1/::1.
Reject URL userinfo/query/fragment and invalid host/port/text. Append
/chat/completions while preserving base path such as /v1. Read bearer key locally.
No key/root/settings enter portable descriptors or Operations.

The fixed request uses text Chat Completions, n=1, stream=false and function tools.
No SSE, Responses, multimodal, legacy functions, automatic retry or failover.
Models requiring extra generation controls/custom CA need a reviewed extension;
unsupported configuration fails explicitly. Use exact Req ==0.7.5 with a fresh
Req.Request.new plus pinned Req.Steps.attach so global Req defaults/plugins cannot
alter transport. Explicit retry/redirect false, raw/identity processing, all-status
bounded callback and explicit overflow marker remain required. Callback halt can
return success: reject overflow before decode even for a valid JSON prefix.

Exactly one choice is accepted. stop is final text with no calls; tool_calls must
contain a complete valid batch. Refusal, length/content_filter, malformed/unknown
action fields and unsupported finish shapes fail. Supported envelope metadata:
choices/id/object/created/model/usage/system_fingerprint/service_tier; choice keys:
finish_reason/message/index/logprobs. Assistant keys: role/content/tool_calls/refusal.
Other fields are conservatively rejected, including harmless unknown annotations.
Only supported assistant fields are retained; top-level metadata is not retained.

| Boundary | Limit |
| --- | --- |
| Context | 128 messages, 1 MiB JSON |
| Full native request/incoming reply, HTTP request/response, normalized reply | 1 MiB each |
| Catalogue | 64 descriptors, 16 KiB each, description 4096 bytes |
| Tool batch | 1..8 calls, unique IDs 1..128 UTF-8 bytes, arguments 16 KiB each |
| Schema string length | maximum/default 16384 codepoints |
| Native progress | 8192 serialized bytes per event |
| Workspace relative path | 4096 UTF-8 bytes, 32 components |
| Workspace retained text | default/cap 65536 bytes, local max_bytes 1..65536 |

Byte caps apply to complete serialized envelopes, not only values. Runtime's
Operation ceiling can be smaller than Harness request limits: the adapter must
reject oversized executable descriptions explicitly, never truncate arguments.
Retained-byte bounds do not guarantee hard RSS, header/transport or parser-depth
bounds. Admission limits concurrency.

WorkspaceRead settings accept only root/max_bytes. Invoke accepts only relative
path arguments. Validate root ancestors as nonsymlink directories and every path
component using lstat. Reject absolute/empty/NUL/dot/dotdot/backslash/empty segments,
symlinks, non-directory intermediates and nonregular leaves. Open raw read-only,
fstat regular type/inode/device, read max+1 sentinel, always close in after.
Return `%{text: binary, bytes: retained_bytes, truncated: boolean}`. Retained UTF-8
must be valid. At a split codepoint, observed sentinel bytes must permit valid
completion, rejecting overlong/surrogate/out-of-range sequences. Drop a genuinely
incomplete truncated codepoint; incomplete EOF fails. Beyond max+1 is not scanned.

Provision a dedicated trusted permitted-content local tree with controlled
ancestors/backing writers/mounts, preferably OS read-only. This is not atomic OS
confinement: lstat/open TOCTOU, raced-in FIFOs, hardlinks/mounts/privileged writers,
non-snapshot content and storage stalls remain possible. No shell/write/listing,
fallback root, native helper or hostile-filesystem sandbox exists.

### 4. Validation & Error Matrix

| Condition | Observation |
| --- | --- |
| Unsupported profile/request fields | invalid_profile / invalid_request |
| Catalogue mismatch/schema violation | invalid_catalogue / invalid_arguments |
| Malformed sibling/duplicate ID/oversized batch | invalid_tool_batch; no returned executable batch |
| Missing/orphan/out-of-order result history | invalid_messages before transport |
| Envelope/context overflow | request_limit / response_limit / context_limit |
| HTTP failure/timeout/TLS | safe transport/provider error, no retry/fallback |
| Non-2xx / overflow / unexpected encoding | http_status / response_limit / unsupported_encoding |
| Malformed/refused/incomplete reply | invalid_reply, invalid_json, unsupported_reply, refused or incomplete_reply |
| Cancellation before invocation | cancelled |
| Unsafe path/config/missing file | workspace_unavailable; no host path exposed |
| Invalid observed text | invalid_utf8 |

Do not log raw errors/bodies/prompts/keys/roots. Native hook exceptions remain local
caller errors; HTTP adapter normalizes unexpected exceptions to provider_failure.

### 5. Good/Base/Bad Cases

Good: validate full batch, map each name/profile through allowlisted adapter data,
execute through Runtime, and join ordered correlated tool observations.
Base: empty catalogue text request needs no workspace service on authority.
Bad: dispatch valid siblings before discovering invalid arguments, accept mismatched
catalogue keys, inherit arbitrary Req defaults, truncate arguments, or call lstat
checks an adversarial sandbox.

### 6. Tests Required

Preserve independent Harness tests (no sibling apps), canonical catalogue/history,
malformed native data, combining-mark codepoint limits and complete envelope caps.
Actual TCP/TLS fixtures must verify exact wire path/auth/body, no second request
on redirect/429/500/timeout, success/error/chunked overflow with valid prefix,
encoding/JSON failures, global Req-default isolation and self-signed TLS rejection.
Workspace tests cover all codepoint split widths, invalid sentinel/incomplete EOF,
root/component symlinks, traversal/nonregular/device/FIFO and repeated fd cleanup.
Local tests are not a paid/live provider or physical-host acceptance record.

### 7. Wrong vs Correct

Wrong: put root/key/Runtime refs in native descriptors, assume strict model output
removes local validation, or interpret timeout as upstream rejection.
Correct: keep settings on executor, pass neutral local Context hooks, validate all
calls locally and preserve Runtime uncertainty and one-attempt semantics.
