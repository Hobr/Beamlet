# Child 2 native Harness handoff

Independent child-2 review and scoped repairs passed; see check-report.md. No task state, index, commit,
backend spec, parent artifact, or other application's source was edited by this
worker. Child 1 remains intact. The source of truth for this seam is
`apps/beamlet_harness/lib/beamlet/harness/` and its behavioral tests.

## Public native API

- `Beamlet.Harness.Model.complete(request, settings, context)` behaviour:
  `{:ok, reply_map} | {:error, safe_atom}`. Concrete OpenAICompatible supports
  `complete/2` with an empty Context default; Deterministic implements `/3`.
- Request: `%{messages: [string_key_message], catalogue: catalogue_map}`. Settings
  are separate local deployment data. Catalogue does not contain callable modules.
- Reply: `%{kind: :text | :tool_calls, content: binary | nil, calls: [call],
  assistant: original_assistant_message}`. Call: `%{id: opaque_binary,
  name: registered_string, arguments: decoded_string_key_map}`. No atoms are
  created from returned text. Original order/IDs and assistant metadata survive.
- `Beamlet.Harness.Tool.descriptor/0` and `invoke(arguments, settings, context)`:
  `{:ok, map} | {:error, safe_atom}`. WorkspaceRead and Tools.Deterministic also
  provide `invoke/2`. Models.Deterministic accepts local `%{reply: wire_reply}`;
  Tools.Deterministic is a bounded `echo` fixture. Both use native hooks.
- `Catalogue.validate(catalogue)` rejects malformed maps and keys differing from descriptor names.
  `Catalogue.new([descriptor]) -> {:ok, catalogue_map} | {:error,
  :invalid_catalogue}`. Descriptor has exactly string keys `name`, `description`,
  `parameters`; catalogue is keyed by name. `Catalogue.batch(wire_calls, catalogue)`
  validates **all** members before returning any executable normalized calls.
- `OpenAICompatible.validate_request(request)` is shared by the deterministic model and HTTP adapter; it checks catalogue, complete ordered history, allowed request keys and the full native 1 MiB envelope.
- `Arguments.schema?/1 -> boolean`, `Arguments.validate(value, schema) -> :ok |
  {:error, :invalid_arguments}`. Schema: shallow object/properties/required/
  additionalProperties, primitive string/integer/number/boolean, typed enum,
  string minLength/maxLength and numeric minimum/maximum. No arrays, nested
  objects, refs, pattern, unions or general JSON Schema. Omitted required means
  none; omitted additionalProperties means false. Explicit true permits extra
  JSON primitive values only. Names match `[a-zA-Z0-9_-]{1,64}`.
- `%Beamlet.Harness.Context{progress: nil | callback/1, cancelled?: nil |
  callback/0}` is local only. `cancelled?/1`, `emit/2`, `append(messages,
  additions)` are public. Append rejects growth; it never evicts messages or
  drops pairs. Provider cancellation is checked before work; cancellation during
  HTTP/file IO is owned by the outer worker lifecycle. It does not undo upstream
  acceptance. Hook exceptions are local caller errors (model adapter returns
  `:provider_failure`). Provider emits at most one fixture lifecycle event;
  concrete HTTP adapter emits none. Adapter callbacks own runtime credit/rate
  translation and must not enqueue unrestricted messages.
- `%Beamlet.Harness.Environment{id: opaque_label}` is a neutral data descriptor;
  the composition adapter validates and resolves labels. No root, PID, resource
  pool, OperationRef or credential belongs in it.
- `WorkspaceRead.validate_root(absolute_root) -> {:ok, File.Stat.t()} |
  {:error, :invalid_root | :unsafe_path}`; also checked at each invocation.

## Model subset, local settings, failures

Executor profiles resolve a portable allowlisted profile ID to
`%{base_url: "https://host/v1", model: "configured-name", key_env: "LOCAL_KEY_ENV",
  timeout_ms: 5000}`. The key is read only on the executor, never included in a
catalogue/Operation. Default timeout is 5000 ms; allowed 1..60000 ms. Base URL
rejects userinfo/query/fragment; HTTP is accepted only with
`allow_local_http: true` and localhost/127.0.0.1/::1. No arbitrary Req options or
TLS verification overrides are accepted. Custom CA settings and optional
model-specific generation parameters are not exposed. Unknown profile keys (including
temperature, max_tokens, TLS/Req overrides) and unknown request keys are rejected,
not silently ignored. Workspace settings accept only root/max_bytes. This minimal
subset works with models accepting the standard fixed request; models requiring
extra token/generation controls need a separately reviewed profile extension.

POST appends `/chat/completions` to the configured base (retains `/v1`). Body
contains configured model, messages, stream=false, n=1 and standard function tools
when catalogue is nonempty. No SSE, multimodal, Responses, legacy functions,
custom actions or automatic retries/failover. Retry/redirect are explicitly false,
identity requested, raw response handled by an all-status bounded callback before
JSON decode. Overflow uses explicit private marker and always fails even if the
retained prefix is valid JSON. Unexpected content encoding fails closed. TLS peer
verification stays enabled. A fresh Req.Request with pinned Req.Steps is used;
global Req defaults/plugins/adapters/parameters cannot alter it. Whole-operation deadline remains the caller's job.

Messages use string keys: system/user/assistant content strings; assistant with
complete function calls and string-or-null content; tool message with content
string and original tool_call_id. A tool batch must be followed by exactly one
result per ID **in original order** before another message/model step. Adapter
must join concurrent results by ID, then append in that order. Missing/duplicate/
out-of-order results fail before transport. Exactly one assistant choice is
accepted. `stop` yields text only; `tool_calls` yields a complete validated batch.
Refusal, length/content_filter, missing/unknown finish, deprecated/unknown action
fields, malformed arguments, duplicate IDs or unsupported tool type fail before
any call is returned. Unknown assistant fields are conservatively rejected (including harmless annotations).
Envelope fields are limited to choices/id/object/created/model/usage/system_fingerprint/
service_tier; choice fields to finish_reason/message/index/logprobs. Those metadata
fields are accepted but only original assistant fields are retained in the reply.
Unknown envelope/choice fields are rejected, including unsupported action fields.

Safe errors include `:invalid_profile`, `:invalid_request`, `:invalid_messages`,
`:invalid_catalogue`, `:context_limit`, `:request_limit`, `:transport`,
`:provider_failure`, `:response_limit`, `:unsupported_encoding`, `:http_status`,
`:invalid_json`, `:invalid_reply`, `:unsupported_reply`, `:refused`,
`:incomplete_reply`, `:invalid_tool_batch`, `:cancelled`. No raw exception, body,
prompt, bearer key, root or host path is included. Transport failures/timeout do
not prove the upstream request was unaccepted. No provider logging is added.

## Bounds

| Boundary | Bound |
| --- | --- |
| Context | 128 messages, 1 MiB JSON |
| Serialized complete native request / HTTP request / response | 1 MiB each |
| Serialized normalized reply | 1 MiB (including duplicated assistant data) |
| Catalogue | 64 descriptors, 16 KiB JSON per descriptor, description 4096 bytes |
| Tool batch | 1..8 calls; unique ID 1..128 UTF-8 bytes; arguments 16 KiB each |
| Schema string maxLength | 16384 codepoints; default same |
| One local progress event | 8192 serialized bytes |
| Workspace path | 4096 UTF-8 bytes, 32 components |
| Workspace read | default/cap 65536 bytes; local max_bytes 1..65536 |

Limits are application retention/serialized bounds, not hard RSS limits. HTTP
headers/transport chunks/JSON parser depth and allocations remain outside the
retained body bound. Runtime admission controls concurrency. Invalid executable
arguments are rejected, never truncated. Tool output is `{text, bytes, truncated}`
as atom-key map; bytes counts retained text. JSON escaping of 64 KiB text remains
below the 1 MiB outer result bound. Read max+1 sentinel; truncate to the largest
valid UTF-8 prefix within max, including split-codepoint boundaries. Invalid bytes
in retained text fail. When the retained prefix ends mid-codepoint, observed sentinel
bytes must permit a valid completion (including overlong/surrogate/range checks).
A genuinely incomplete truncated codepoint is dropped; untruncated incomplete text
fails. Beyond max+1, the omitted suffix is not scanned/validated.

## Workspace provisioning and downstream adapter

Workspace settings `%{root: absolute_trusted_root, max_bytes: 65536}` remain local.
Only `%{"path" => relative_utf8_path}` comes from the model. Root and all ancestor
components must be nonsymlink directories. Reject empty, absolute, NUL, dot/dotdot,
empty components, backslashes, excessive path depth/length, intermediate symlinks,
leaf symlinks, directories, FIFO/socket/device/nonregular leaves. No decoding,
shell expansion, listing, writes or fallback roots. Open read-only raw descriptor,
compare regular type/inode/device with lstat, read bounded bytes, close in after.

**Deployment condition:** dedicate a permitted-content local tree, control its
ancestors/backing writers/mounts, preferably provision OS read-only. This is not
an OS sandbox: lstat/open are TOCTOU, hardlinks and bind mounts are undetected,
raced-in FIFOs may block before fstat, privileged/hostile writers are not contained,
and backing-tree writes remain possible through another mount. Reads are not
snapshots; storage latency is not guaranteed. No native helper/openat2 is claimed.

Child 3 registers configured native provider/Tool modules locally in its own
allowlist, maps portable profile/environment IDs to capabilities and placement,
then resolves local settings at executor entry. Runtime handlers call
`OpenAICompatible.complete(request, resolved_settings, native_context)` or
`WorkspaceRead.invoke(call.arguments, resolved_settings, native_context)`.
Build Catalogue on authority without model key, root, workspace process or HTTP
call. Return only normalized bounded data to Agent; Agent appends original
assistant then correlated Tool observations encoded as bounded content strings.
Harness itself imports no Actions/Runtime/Agent/Phoenix and activates no authority
or runtime tree.

## Dependencies and review boundary

Harness declares exact Req ==0.7.5 and direct Jason ~>1.4. No Plug dependency was
needed: tests use actual TCP/SSL sockets. Root lock additions are narrowly required
Req 0.7.5 plus Finch 0.24.0, Mint 1.11.0, NimbleOptions 1.1.1, NimblePool 1.1.0;
all existing locked versions retained. Production dependency closure contains only
HTTP/JSON/OTP dependencies, no sibling Beamlet application or Phoenix.

Independent trellis-check completed with scoped repairs; parent retains the final integration gate. Backend spec updates and final
commit/archive are deliberately deferred to parent delivery under write scope.
No real endpoint/paid request, physical multi-host, hostile-filesystem isolation,
or custom provider feature compatibility is attested here.


## Operator-run live-provider smoke path (not executed)

After separately authorizing credentials and spending, the operator may run the
native `OpenAICompatible.complete/2` from IEx on the executor with a configured
HTTPS base/model/key_env profile, a one-message user request and empty catalogue.
Check for a bounded text reply, then repeat with the WorkspaceRead descriptor and
a prompt asking for one known fixture path; inspect the normalized opaque ID and
arguments without dispatching automatically. Do not print settings, raw responses
or credentials. This only probes that configured endpoint/model subset. These
paid/live calls are never part of ExUnit and have not been run by either worker.
The outer Agent/Runtime adapter owns deadlines, worker termination, progress credit
and local cancellation during IO; Harness checks cancellation before invocation
only. No evidence here establishes upstream cancellation, race-safe teardown or
physical-host placement. Environment.id is a data struct, not a validated authority;
child 3 must validate/resolve its allowed label. Context.append enforces bounds only;
validate_request enforces complete message pairs before either model runs. Malformed
hook functions or their exceptions remain caller errors, as described above.
