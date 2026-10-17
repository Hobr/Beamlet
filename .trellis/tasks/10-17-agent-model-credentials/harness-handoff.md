# Harness component handoff

Harness implementation complete on feat/agent-model-credentials. Only Harness source/tests and this handoff were edited. No dependencies, staging, commits, task/branch state changes, external paid/live calls or sibling-lane edits.

## Consumer APIs (intentional migration; no compatibility shims)

`Beamlet.Harness.Model` now lives in `lib/beamlet/harness/model.ex` and owns the behaviour:

```elixir
validate_invocation(%{config: string_key_json_object, credentials: string_key_json_object})
# :ok | {:error, safe_atom}
complete(%{messages: messages, catalogue: catalogue}, invocation, %Context{})
# {:ok, %{kind: :text | :tool_calls, content: binary_or_nil, calls: calls}}
# | {:error, safe_atom}
```

Native reply calls are exactly `%{id: binary, name: binary, arguments: decoded_object}` (atom keys). There is no `assistant` field. `Model.validate_reply(reply, catalogue)` returns `:ok` or a safe error; consumers MUST validate replies before use. `Model.assistant_message(validated_reply)` constructs canonical string-key assistant history; `Model.canonical_call(native_call)` converts an exact native call to history shape (or nil for malformed shape). These conversion helpers assume a previously validated reply and perform no provider parsing.

`Model.validate_request/1` validates exact messages/catalogue keys, catalogue schemas, ordered complete history and 1 MiB total request. `Model.validate_history/2` independently checks catalogue, Context bounds and history. Canonical history:

- `%{"role" => "system" | "user" | "assistant", "content" => text}`
- `%{"role" => "assistant", "content" => text_or_nil, "calls" => [%{"id" => id, "name" => name, "arguments" => decoded_object}]}`
- `%{"role" => "tool", "call_id" => id, "content" => text}`

History requires every pending call observation once in original order before another message. Tool batches require 1..8 unique nonempty UTF-8 IDs <=128 bytes and <=16 KiB encoded decoded arguments, and are validated completely before returning any executable calls. `Catalogue.batch(canonical_string_key_calls, catalogue)` returns ordered native atom-key calls. It rejects OpenAI wrappers and JSON argument strings. Context retains 128 messages/1 MiB without eviction; malformed improper message lists now fail safely.

`Model.validate_invocation/1` is common validation, NOT adapter validation. It checks exact config/credentials outer keys, plain string-key JSON objects, nesting <=24, config/credential JSON <=16384 bytes each, credentials <=32 fields and 1..128-byte top-level names, ordinary config forbidden secret/root names, and no root/workspace_root keys within credentials. `Model.json?/1` exposes strict JSON data checks. Agent binding placement and full Operation envelope validation remain the consuming lanes' responsibility; Harness does not depend on Actions/Runtime/Agent/Node.

`Model.default_providers/0` returns `%{"openai-compatible" => OpenAICompatible, "deterministic" => Deterministic}`. `Model.provider_id?/1` checks the portable ID syntax. `Model.validate_registry/1` validates a plain trusted local map, <=32 entries, valid string IDs and loaded module implementations exporting both callbacks. Returns `:ok` or `{:error, :invalid_model_providers}`. Never derive modules/atoms from caller IDs. Model's sole concrete OpenAI reference is its built-in registry entry, not wire parsing.

## Provider invocation shapes

OpenAICompatible.complete/2 or /3 takes:

```elixir
%{config: %{"base_url" => "https://example.test/v1", "model" => "model-name",
            "timeout_ms" => 5000, "allow_local_http" => false},
  credentials: %{"api_key" => "explicit-key"}}
```

base_url/model are required; timeout_ms/allow_local_http are optional with shown defaults. The key is UTF-8 1..4096 bytes without CR/LF. Unknown fields/key_env/legacy flat settings are rejected, with no environment lookup. Its pure `validate_invocation/1` returns `:invalid_profile` for malformed invocation/config/credentials. `complete` revalidates direct invocations. All canonical -> OpenAI message conversion, argument JSON encoding/decoding, tools, response choice/finish/refusal normalization now reside in this adapter. `normalize(wire_envelope, catalogue)` remains an adapter-only codec for direct adapter tests; generic callers must use Model validators and never reconstruct envelopes. The former `OpenAICompatible.validate_request/1` was removed.

Deterministic.complete/2 or /3 takes exactly:

```elixir
%{config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}},
  credentials: %{}}
# or kind "tool_calls", content binary/nil,
# calls [%{"id" => id, "name" => name, "arguments" => decoded_object}]
```

Its fixture is JSON data, not an OpenAI response. Only reply is accepted in config and credentials must be empty. Common validation plus fixture shape validation runs in `validate_invocation/1`; complete additionally validates request and native reply against the actual catalogue. It retains cancellation and progress hooks without invoking OpenAI codecs.

## Changed files

- apps/beamlet_harness/lib/beamlet/harness.ex — move Model into cohesive module; update module documentation.
- apps/beamlet_harness/lib/beamlet/harness/model.ex — new neutral contracts/validators/converters and trusted registry helpers.
- apps/beamlet_harness/lib/beamlet/harness/catalogue.ex — decoded canonical batches only.
- apps/beamlet_harness/lib/beamlet/harness/context.ex — malformed improper list fails context_limit.
- apps/beamlet_harness/lib/beamlet/harness/models/open_ai_compatible.ex — explicit invocation, provider-owned codecs; preserved transport.
- apps/beamlet_harness/lib/beamlet/harness/models/deterministic.ex — neutral JSON fixtures and common validation.
- apps/beamlet_harness/test/beamlet/harness_test.exs — migrate existing batch/history/deterministic assertions without dropping behavioral checks.
- apps/beamlet_harness/test/beamlet/http_test.exs — explicit credentials, canonical history -> actual wire assertions, concurrent independent invocation/auth isolation.
- apps/beamlet_harness/test/beamlet/model_test.exs — new independent alternative protocol and neutral/invocation/registry limits tests.
- .trellis/tasks/10-17-agent-model-credentials/harness-handoff.md — this handoff.

## Executed checks and evidence

All commands used `ERL_FLAGS='+S 2:2'`:

- Root: `mix format 'apps/beamlet_harness/{lib,test}/**/*.{ex,exs}'` — pass; /tmp/harness-format.log.
- Root: `mix format --check-formatted 'apps/beamlet_harness/{lib,test}/**/*.{ex,exs}'` — pass; /tmp/harness-format-check.log.
- apps/beamlet_harness: `mix compile --warnings-as-errors` — pass; /tmp/harness-compile.log.
- apps/beamlet_harness: `mix test --seed 631927` — **31 passed**, 6.2 seconds; /tmp/harness-tests.log. TCP and self-signed TLS fixtures actually ran; expected bad-certificate notices are fixture evidence.
- Root: `git diff --check` — pass; /tmp/harness-diff-check.log.

Preserved TCP/TLS/path/auth/body/ordered call identity/one-attempt redirect+429+500+timeout/all-status and chunked overflow/encoding/global Req defaults isolation. Existing WorkspaceRead filesystem/UTF-8/fd cleanup and primitive schema tests all ran unchanged. New alternative provider uses variant config, nested session/bearer authentication and tuple internal response representation; it completes neutral tool history -> final text without OpenAI conversion. Concurrent direct HTTP invocations assert model/key pairing and absence of credentials from body. Normal neutral history/replies exclude the alternative fixture credential.

Development iterations exposed and fixed malformed invocation normalization and invalid UTF-8 being mislabeled as response_limit. Initial format command using directories found no files; corrected to explicit glob above. Logs above reflect final successful gates. Elixir diagnostics initially reported an unavailable language tool for the new Model file, while subsequent edited-file probes reported clean; no complete repository LSP coverage is claimed.

## Remaining work and limits

Agent/Node must migrate old flat static model profiles and Deterministic OpenAI fixture settings. Replace calls to OpenAICompatible.validate_request with Model.validate_request; replace wire-envelope reply reconstruction/assistant retention with Model.validate_reply and Model.assistant_message; append tool observations with call_id. Pass canonical decoded batches to Catalogue.batch. Agent owns immutable provider/config/credentials/placement bindings and must validate both common invocation and selected registered adapter before acceptance. Handler must revalidate and pass explicit invocation, including context.credentials from the Operation lane. Use trusted registry helpers locally; Node must normalize registry errors to invalid_node_configuration and combine advertised capability bounds with Tools. Harness registry validation performs no model network call.

Operation/Runtime credentials forwarding and full protocol/deployment byte caps are not implemented here. Node end-to-end alternative provider, two Agents sharing executor, remote VM/lifecycle/credential projection/child inheritance acceptance, current fixtures/scripts/examples/spec migration and copied release/Web gates remain for later owners. Existing sibling code still references the removed legacy contracts and is expected to require migration; no umbrella acceptance, Credo/Dialyzer, distributed VM or release result is claimed. No physical hosts or paid/live models were tested. Provider echoes and administrator memory inspection remain outside generated-projection guarantees.
