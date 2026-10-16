# Provider, read-only workspace, and product release research

Research-only evidence for option-B MVP planning, inspected 2026-10-16. No implementation, dependency fetch into the project, release assembly, credentials, or paid requests. Recommendations below are **not implemented guarantees**.

Task routing: `task.py current --source` returned `(none)` / `Source: none` (exit 1); the explicitly assigned task exists and its `task.json` says `planning`. No pointer or task-state changes were made.

## Summary / blockers

- **Req 0.7.5 is a real, non-retired stable Hex release.** Its actual package was verified against the version-tagged source. POST, explicit `retry: false`, `redirect: false`, synchronous chunk callbacks, TLS options, and local test adapters are available.
- **Important implementation traps:** callback `{:halt, ...}` is not automatically a size-limit error; a collectable does not enforce the same bound for error statuses; compression defaults **off** in 0.7.5; receive timeout is not an overall deadline. Preserve independent operation deadlines.
- **OpenAI-compatible means a declared subset**, not compatibility with every provider/model: text Chat Completions, non-streaming, function tools, opaque tool-call IDs, local argument validation, explicit finish/refusal handling. Generic progress remains supported without SSE/token streaming in this adapter.
- **Workspace confinement is conditional, not an OS sandbox.** OTP 29 has no documented `openat2`/no-follow path-opening API. Component `lstat` checks plus bounded descriptor reads cannot close all TOCTOU races. Use a trusted, non-adversarial local filesystem assumption for the proposed implementation (prefer an OS read-only mount with no externally writable backing tree); this assumption awaits final parent-plan review; do not claim adversarial confinement.
- **Current production boot is blocked without a web secret**, even if the release excludes web, because `config/runtime.exs` unconditionally fetches `SECRET_KEY_BASE` in production. Gate web-only runtime config and verify the built release closure. The backend dependency graph and release entry point do not exist yet.
- No additional product decision is required within the supplied scope. The above are implementation/review gates, not reasons to expand into a sandbox, full OpenAI API, or web product.

## 1. Repository evidence

Read `architecture.md` in full, task `prd.md` / `task.json`, all `.trellis/spec/backend/*.md`, root and six child `mix.exs` files, `mix.lock`, and `config/{config,prod,runtime}.exs`.

- Architecture §§3–5: concrete HTTP and workspace providers belong in independent Harness; operation adapters belong in Agent; Node composes role services. Runtime must not depend on Harness/Agent. Loading Agent adapters must not activate authority services.
- Architecture §§7–10: one attempt per operation; no automatic replay after ambiguity; complete tool arguments validated before execution; progress is optional/bounded and distinct from the terminal result; stopping a worker does not prove a provider stopped or billing was avoided.
- Non-web child manifests currently have no active dependencies. Root-only dependencies are not child runtime dependencies. `mix.lock` has Jason 1.4.5 and Plug 1.20.3 through web, but **no Req, Finch, or Mint**. Their proposed versions must not be described as already locked/tested.
- Root `mix.exs` has no `releases:` definition and does have a Phoenix code-reloader listener. Web has its own Phoenix/Bandit graph. Shared compile-time config includes web/asset entries; runtime config currently raises for a missing web secret in every production deployment.
- Local toolchain observed: Elixir **1.20.4**, Erlang/OTP **29**, ERTS **17.1**. Source research below uses Elixir v1.20.4 / OTP-29.0; the installed OTP patch/build is not inferred from its major-version banner.

## 2. Req 0.7.5

### Primary evidence and version confidence

- [R1: Hex release metadata](https://hex.pm/api/packages/req/releases/0.7.5): version `0.7.5`, inserted `2026-10-06`, `retirement: null`, Elixir `~> 1.15`; no listed security advisories at inspection. This is not a security audit.
- [R2: shipped package](https://repo.hex.pm/tarballs/req-0.7.5.tar): fetched **in memory**, SHA256 `576853c4bf403faa3c1fa5d093e0759227083b78f8a6864c67d62c0a9c45514d`, matching R1. Shipped `mix.exs`, `lib/req.ex`, `lib/req/steps.ex`, `lib/req/finch.ex`, and `lib/req/plug.ex` byte-match the GitHub `v0.7.5` tag.
- [R3: Req public API, pinned tag](https://github.com/wojtekmach/req/blob/v0.7.5/lib/req.ex): `new/1,2`, `post/2`, `run/2`, `into`, auth/JSON/options documentation. [Versioned docs](https://hexdocs.pm/req/0.7.5/Req.html) are preferable to the moving unversioned page.
- [R4: response steps](https://github.com/wojtekmach/req/blob/v0.7.5/lib/req/steps.ex), [Finch adapter](https://github.com/wojtekmach/req/blob/v0.7.5/lib/req/finch.ex), [Plug adapter](https://github.com/wojtekmach/req/blob/v0.7.5/lib/req/plug.ex), [Response struct](https://github.com/wojtekmach/req/blob/v0.7.5/lib/req/response.ex), [test helpers](https://github.com/wojtekmach/req/blob/v0.7.5/lib/req/test.ex).

**Confidence:** high for Req APIs/behavior by package/source inspection; no Req execution in this repository. Req requires Finch `~> 0.21`, Jason `~> 1.0`, MIME `~> 2.0.6 or ~> 2.1`; Plug `~> 1.0` is optional. An exact Req pin does **not** fix transitive versions: retain/review `mix.lock` when implementation is approved.

### Verified API behavior

| Concern | Evidence / exact API |
| --- | --- |
| POST | `Req.post(url_or_request, options)` returns `{:ok, %Req.Response{}}` or `{:error, exception}`. Use `json: payload`, `auth: {:bearer, key}`; inspect HTTP status explicitly rather than treating any returned response as model success. |
| No retries | `retry: false` disables Req's retry response/error steps. The 0.7.5 default is `:safe_transient` (GET/HEAD), not a guarantee to rely on implicitly for POST. Do not add application retries or retry-based endpoint failover. |
| No redirects | `redirect: false` disables automatic 301/302/303/307/308 following. Treat 3xx as a bounded provider error, not a second request. Default is `true`. |
| Bounded body | `into: fn {:data, chunk}, {req, resp} -> {:cont, {req, resp}} \| {:halt, {req, resp}} end`. The callback must accumulate bytes itself. Finch calls it for data at **all statuses**, after status/headers have been received. |
| Overflow handling | Returning `{:halt, {req, resp}}` can still produce `{:ok, resp}`. Mark overflow in `resp.private[:beamlet_body_limit]` and reject it **before** JSON parsing/normalization, even if the retained prefix is valid JSON. Do not accept truncated model replies. |
| Collectable trap | `into: collectable` uses the collectable only on status 200; other bodies accumulate normally. Do not use that path as a universal response-size guard. |
| Compression | 0.7.5 defaults to `compressed: false`. `raw: true` disables automatic decompression and decoding; decompression is also skipped with `into` streaming. Explicitly request identity encoding and reject unexpected content encodings, rather than manually inflating unbounded data. Older examples/default assumptions may differ. |
| TLS / connection | `connect_options: [timeout: connect_ms, transport_opts: [verify: :verify_peer]]`; custom CA via `cacertfile:` in `transport_opts`. Do not use the documentation's development `verify_none` example. |
| Timeouts | `receive_timeout: idle_ms`, `request_timeout: budget_ms`; connection timeout is separate. Finch-specific `finch: [pool_timeout: pool_ms]` is supported, but **cannot be combined with `connect_options:`**. Configure one supported pool/options path rather than mixing them. |
| Testing | `plug: fn conn -> ... end` or `plug: {Req.Test, name}`; `Req.Test.stub/2`, `expect(name, n \\ 1, plug)`, `verify_on_exit!/1`, `allow(name, owner_pid, worker_pid)`, `json/2`, `transport_error/2`. Plug is required for these helpers. `adapter: Module` is supported for an alternative test seam; function adapters are deprecated in 0.7.5. |

[R5: Finch v0.21.0 request documentation](https://github.com/sneako/finch/blob/v0.21.0/lib/finch.ex) states `request_timeout` is **HTTP/1-only and best effort**; `receive_timeout` is per chunk, and pool checkout can raise. This is a verified compatible baseline, **not the repository's resolved Finch version**. Recheck the actual lock resolution. Keep the coordinator's monotonic operation budget and bounded worker cleanup independent of HTTP-client timeouts; handle expected HTTP exceptions at the provider boundary.

[R6: Mint v1.7.1 TLS source](https://github.com/elixir-mint/mint/blob/v1.7.1/lib/mint/core/transport/ssl.ex) demonstrates peer verification, hostname checks/SNI, and OS CA loading via `:public_key.cacerts_get/0` with fallback. This is a compatible example, not a selected Mint pin. Verify the resolved Mint and target machine's CA store. TLS failures must fail closed; HTTP should be limited to explicit local test/development configuration, not automatic fallback.

### Recommendations (not implementation)

1. Declare exact `{:req, "== 0.7.5"}` in the provider-owning child (`beamlet_harness`), not only at root. Declare Jason there if directly calling `Jason.decode/1`; do not depend on web's Jason. Add Plug as a test-only child dependency if using Req.Test; Plug does not require Phoenix and need not enter the production Harness closure.
2. Configure endpoint/model/provider profile on the executor, never from arbitrary tool/model input. Validate HTTPS URL, disallow userinfo/fragment, keep bearer credentials executor-local, and redact errors/logs. Use a fresh controlled Req configuration rather than inheriting unreviewed global defaults/plugins.
3. Use `Req.post/2` with explicit `retry: false`, `redirect: false`, `raw: true`, `compressed: false`, `headers: [{"accept-encoding", "identity"}]`, and the bounded callback. Track an integer byte count and bounded reversed chunk list in response-private state; halt **before retaining** an over-limit chunk. On successful complete response, concatenate once and explicitly decode/validate. Enforce the same limit on 3xx/4xx/5xx bodies; never log full bodies or Authorization.
4. `Content-Length` is an optional early hint, not the size guard. A callback bound is a bound on retained response data, **not a hard BEAM RSS cap**: transport chunks, headers/trailers, parser allocations, JSON depth, and concurrent requests still consume memory. Cap request/history/tool sizes and concurrency too. Large/deep JSON is a residual parser-resource concern; reject malformed structures before domain work.
5. Test exact POST path/headers/JSON, one request on 429/500/timeout, zero redirect follow-ups, oversized success/error/chunked bodies, explicit overflow marker, unsupported encoding, malformed JSON, and cancellation/late-response handling. Req.Plug stores its fixture response before invoking callbacks: it tests callback logic, not real network memory/backpressure/TLS. Use a local bounded socket server for transport/deadline/TLS tests, not paid endpoints. For manually supervised workers, use explicit Req.Test allowance; allowances and stubs are node-local, not automatically shared with a remote executor.

## 3. Chat Completions text + function-tool subset

### Primary evidence

- [O1: official function-calling guide](https://platform.openai.com/docs/guides/function-calling), page-local extraction: append the assistant tool-call message, execute complete calls, then append tool outputs with the matching `tool_call_id`. Responses may contain zero, one, or multiple calls. The page also covers Responses API; **do not mix its `call_id` / `function_call_output` shapes with Chat Completions**.
- [O2: official OpenAI Python v2.0.0 generated types](https://github.com/openai/openai-python/tree/v2.0.0/src/openai/types/chat), used as an immutable API-schema snapshot, not a proposed dependency: [create params](https://github.com/openai/openai-python/blob/v2.0.0/src/openai/types/chat/completion_create_params.py), [function-tool declaration](https://github.com/openai/openai-python/blob/v2.0.0/src/openai/types/chat/chat_completion_function_tool_param.py), [function tool call](https://github.com/openai/openai-python/blob/v2.0.0/src/openai/types/chat/chat_completion_message_function_tool_call.py), [tool output](https://github.com/openai/openai-python/blob/v2.0.0/src/openai/types/chat/chat_completion_tool_message_param.py), [assistant message](https://github.com/openai/openai-python/blob/v2.0.0/src/openai/types/chat/chat_completion_message.py), [completion/finish reason](https://github.com/openai/openai-python/blob/v2.0.0/src/openai/types/chat/chat_completion.py), [function schema/strict](https://github.com/openai/openai-python/blob/v2.0.0/src/openai/types/shared_params/function_definition.py).
- [O3: official SDK request source](https://github.com/openai/openai-python/blob/v2.0.0/src/openai/resources/chat/completions/completions.py) POSTs `/chat/completions` relative to its API base. The direct [create reference](https://platform.openai.com/docs/api-reference/chat/create) returned HTTP 403 in this worker; this report does not claim to have re-read it successfully. O1 and pinned O2/O3 independently establish the relevant subset.

**Confidence:** high for these documented Chat Completions wire shapes; no claim about every current model or third-party compatible endpoint. A real endpoint/model feature probe remains an optional operator-run check when credentials and spending are approved.

### Recommended minimal wire contract

- Request: configured API base (normally includes `/v1`) plus `/chat/completions`; `model`, bounded `messages`, `stream: false`, `n: 1`; text `system`/`user`/`assistant` messages and `tool` replies. Define base-URL joining so `/v1` is neither stripped nor doubled. No multimodal/custom tools/legacy `functions`/Responses API/SSE in this adapter.
- Function declaration: `{"type":"function","function":{"name":"workspace_read","description":"...","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}}}`. Provider name syntax is bounded ASCII letters/digits/underscore/hyphen, at most 64 chars in O2. Do not invent atom/module names from returned strings.
- Reply: exactly one usable choice for `n: 1`; assistant content string or null, optional refusal, optional bounded tool-call list. Preserve assistant content and tool-call metadata together; null content is normal for tool-only replies. Each call requires a bounded nonempty unique opaque `id`, `type: "function"`, allowlisted function name, and **JSON string** `function.arguments`. Detect duplicates before scheduling any calls.
- Parse the arguments string separately using safe JSON decoding with string keys. Require an object and validate required keys, allowed keys, types/ranges/lengths/enums against the registered catalogue's **declared schema subset**. The source explicitly warns that generated arguments may be invalid JSON or hallucinate fields. `strict: true` is not a substitute for local validation; it is optional/provider-dependent and supports only a JSON Schema subset. Fail closed on unsupported catalogue schema features rather than pretending full JSON Schema support.
- Before any batch dispatch, validate the whole batch and enforce max call count/argument bytes. This prevents a malformed sibling call from causing accidental partial dispatch. Independent valid calls may run concurrently subject to admission/capacity. Join results by ID, not arrival order; store stable original call order for the next model request.
- Append the original assistant tool-call message before results. Every dispatched call's next-model observation is a bounded string `{"role":"tool","tool_call_id":"original-id","content":"..."}`; encode structured success/failure/truncation data as text/JSON. Do not confuse provider tool IDs with OperationRef/execution IDs. No next model step until the chosen join policy has produced all required observations, or the turn has explicitly stopped/failed.

### Recommended normalization table

| Provider reply | Conservative MVP normalization |
| --- | --- |
| `finish_reason: "stop"`, usable text, no refusal/calls | Complete text reply. |
| `"tool_calls"`, complete valid nonempty function-call batch | Tool-call reply; validate all arguments before submitting work. Text may coexist but is not a separate terminal success. |
| `"length"` | Incomplete generation, even if content or arguments appear parseable. Never execute potentially truncated calls. |
| `"content_filter"` | Filtered terminal observation, not a successful empty answer or tool request. |
| Nonempty `message.refusal` | Explicit refusal observation; do not execute calls. A refusal can accompany `"stop"`; checking only finish reason is insufficient. |
| Deprecated `"function_call"`, unknown finish reason, missing/contradictory choice/call shape, unsupported tool type | Explicit unsupported/malformed-provider-reply error. No guessed behavior or implicit retry. |
| Non-2xx status / transport failure / size overflow / invalid JSON | Bounded provider error with safe diagnostics; never a tool batch. Timeout/disconnection does not prove the upstream request was unaccepted. |

No requirement to support every optional field: tolerate harmless extra metadata, but reject unsupported action-bearing shapes. Model output-token controls (`max_completion_tokens` versus deprecated `max_tokens`), system/developer roles, parallel-tool flags, strict schemas, and temperature support vary by backend/model. Keep optional request fields profile-driven; test the declared subset rather than promise universal compatibility. Token limits do not replace response byte limits.

### Non-streaming versus generic progress

`stream: false` concerns the model protocol, not the runtime event contract. Reading HTTP chunks through Req's `into` callback to bound a final JSON response is **not** SSE/model streaming. The first adapter may emit only bounded lifecycle progress (or none); deterministic test providers can emit progress to exercise the generic pathway. Final model text/calls must arrive independently as one complete normalized reply. Do not synthesize token deltas from arbitrary JSON byte chunks or execute partial arguments.

## 4. Linux/OTP read-only workspace confinement

### Primary evidence / limitations

- [F1: Elixir File v1.20.4](https://github.com/elixir-lang/elixir/blob/v1.20.4/lib/elixir/lib/file.ex): `File.lstat/2` uses `:file.read_link_info/2`; unlike `stat`, it identifies a **final-component** symlink. `File.open/2` raw descriptors require `:file` functions, not the generic IO API.
- [F2: OTP-29.0 file API and embedded docs](https://github.com/erlang/otp/blob/OTP-29.0/lib/kernel/src/file.erl): `:file.open(path, [:read, :raw, :binary])`, `:file.read_file_info(fd, [{:time, :posix}])`, `:file.read(fd, n)`, `:file.close(fd)`. Metadata includes type, inode/device, and size; bounded reads return `{:ok, binary}`, `:eof`, or `{:error, reason}`. `:exclusive` means exclusive **creation for writing**, not read confinement. `:raw` means local/owner-process descriptor access, **not symlink safety**.
- [F3: OTP primitive implementation](https://github.com/erlang/otp/blob/OTP-29.0/erts/preloaded/src/prim_file.erl) and F2 expose no documented `nofollow`, `non_block`, or directory-FD-relative `openat2` mode. Do not assume adding such atoms to `File.open` is supported.
- [F4: Linux openat2(2)](https://man7.org/linux/man-pages/man2/openat2.2.html): `RESOLVE_BENEATH` / `RESOLVE_IN_ROOT` and `RESOLVE_NO_SYMLINKS` are kernel-supported path-resolution controls; ordinary `O_NOFOLLOW` affects only the final component. These illustrate the missing stronger primitive, **not an OTP API or MVP dependency**. The man page is moving; no reliance on newer optional flags.
- F2 explicitly warns that NFS, FIFOs, devices, etc. can hang IO threads indefinitely. An operation timeout or killing a BEAM worker is not proof that a blocked OS/file operation has stopped.

**Local read-only probe:** on installed Elixir/OTP, `File.lstat("architecture.md")` reported `:regular`; opening it with `[:read, :raw, :binary]`, descriptor stat, and `:file.read(fd, 16)` succeeded and returned exactly 16 bytes. Descriptor was closed in `after`. This verifies API availability, not race resistance or the unimplemented Tool.

### Recommendations (best effort under approved assumptions)

1. Configure a workspace/environment ID and absolute root on the execution node; never accept a root/absolute host path from the model. Validate the root and its ancestor components as nonsymlink directories at provisioning/startup. Avoid roots whose deployment ancestors are symlinks; the root itself must not be a symlink.
2. Accept a bounded valid UTF-8 relative string path only. Reject empty/NUL-containing paths, absolute paths, `.`/`..` segments, excessive depth/length, and ambiguous separator forms under the declared Linux path policy. Do not URL-decode or shell-expand user input. Inspect traversal segments **before** `Path.expand` can erase them. Compare path components (or root plus separator), never naive `starts_with?(candidate, root)` which accepts sibling prefixes such as `/workspace-other`.
3. Walk each root-relative component with `File.lstat`; require directories for intermediates and a regular file at the leaf. Reject every symlink (including one pointing back inside root), directory leaf, FIFO/socket/device/other, missing file, or permission failure. A final `File.regular?`/`File.stat` alone follows symlinks and is insufficient.
4. Open with `:file.open(path, [:read, :raw, :binary])` in the worker that will read/close it. Immediately descriptor-stat; require regular type and optionally compare inode/device against the pre-open leaf stat. Boundedly recheck component/leaf metadata if desired to detect ordinary churn. Close on every outcome via `try ... after`. These checks reduce mistakes/races but are **not an atomic confinement proof**.
5. Read at most `max_bytes + 1` bytes (or a bounded chunk loop with the same total), not `File.read`/`IO.read(:all)` or unbounded line reads. Return at most `max_bytes`, with explicit truncation if the sentinel byte exists; handle empty EOF. A stat size check is advisory because contents can change. Cap final serialized Tool results too; ensure truncation does not split UTF-8 or produce invalid JSON. For the text-only tool, reject binary/invalid UTF-8 content or explicitly apply a documented bounded encoding policy.
6. Advertise workspace access only on the configured executor and map its opaque environment label in the Agent adapter. No path synchronization, fallback to another root, shell, network fetch, directory recursion, or writes. File permissions/mounts are deployment-owned; do not infer read-only protection from `File.Stat.access`.

### Honest residual risks

- Between `lstat` and open, a directory/leaf can be replaced; checks themselves follow previously resolved ancestors. Descriptor stat cannot prove which ancestor path was traversed. Opening a raced-in FIFO can block **before** fstat can reject it. Hard links and bind mounts can expose content outside a lexical root; symlink rejection does not detect them.
- This does not protect against malicious local filesystem writers, privileged users, arbitrary BEAM code, existing sensitive files/hard links inside the exposed tree, or special pseudo-filesystems. A read-only bind mount prevents writes **through that mount**, not changes through another writable mount/source path. Provision a dedicated permitted-content tree and control other writers/backing mounts; trust/provisioning assumptions must be documented in deployment acceptance.
- Concurrent legitimate edits can yield a mixed/non-snapshot read. There is no content-consistency or freshness guarantee. Regular local files still do not provide hard latency guarantees under failing storage.
- Stronger hostile-filesystem containment would require separately designed OS isolation and/or a native/port helper using suitable kernel primitives. It is not silently provided by this MVP and is not recommended as scope expansion here.

## 5. Product-node release without Phoenix

### Primary evidence

- [M1: Mix release v1.20.4, umbrella section](https://github.com/elixir-lang/elixir/blob/v1.20.4/lib/mix/lib/mix/tasks/release.ex#L848-L889): umbrella releases explicitly list entry applications and include their dependencies automatically; they can select subsets. A suitable planned root entry is `releases: [beamlet_node: [applications: [beamlet_node: :permanent]]]` **after** actual sibling dependencies are declared.
- [M2: same pinned source, runtime configuration](https://github.com/elixir-lang/elixir/blob/v1.20.4/lib/mix/lib/mix/tasks/release.ex#L628-L647): shared `config/runtime.exs` is copied/executed early, before product applications; it must not access Mix. Excluding web from `applications:` does **not** skip the runtime script. [Config v1.20.4](https://github.com/elixir-lang/elixir/blob/v1.20.4/lib/elixir/lib/config.ex) provides `config_env/0` / `config_target/0` without a runtime Mix dependency.
- Repository `config/runtime.exs`: `if config_env() == :prod` immediately loads/raises for `SECRET_KEY_BASE`, then configures `Beamlet.Web.Endpoint`. Root has no release definitions; five non-web child manifests have no sibling graph yet. Merely adding a release entry today would not assemble the intended product.

### Recommendations / validation gates

1. Make the Node dependency closure match architecture: Actions/Runtime/Harness/Agent plus selected HTTP/runtime dependencies; no `beamlet_web`, Phoenix, LiveView, Bandit, or Phoenix.PubSub dependency in core product paths. Req.Test's optional **test-only Plug** is not Phoenix. Do not use `beamlet_web: :load`/`:none` as an exclusion workaround: omit web entirely from backend entry points/closure.
2. Gate the **whole web-only production runtime block**, not just `server: true`. A minimal policy can use an explicit boot setting such as `BEAMLET_WEB_ENABLED=true`, shared consistently with web activation. In enabled production web deployments, missing/invalid web secret must still fail fast; backend-only production must require no dummy web secret. The flag alone does not remove web from a release. Do not test `Application.started_applications()` at runtime-config evaluation (too early), call `Mix.env()`, or load Phoenix just to decide whether to configure it.
3. An alternative release-specific runtime file/build target is supported, but is an engineering alternative, not a need for a new product decision. Whichever selector is chosen, document behavior for both release boot and `mix phx.server` in production and test that web cannot silently boot with its production secret check disabled.
4. Inspect shared `config/config.exs` / `prod.exs` for irrelevant web/asset config and root Phoenix listener. Assembly can compile more umbrella source/dependencies than the resulting release includes; distinguish **build-time tooling** from **shipped runtime closure**. Do not declare success from `Application.started_applications()` alone: inspect `lib/`, `.rel` entries and dependency `.app` files for both absence and transitive dependencies, then boot in an environment without source/deps or web secrets.
5. Planned acceptance commands (not run): `MIX_ENV=prod mix release beamlet_node`; inspect `_build/prod/rel/beamlet_node/lib/` and release `.rel`; boot with `SECRET_KEY_BASE` unset using release `start`/`eval` tooling and inspect loaded/started apps and roles. Verify real model configuration only on executor profiles and authority-only boot without credentials. Assemble and test the web release only if retained in implementation scope; no web product UI is required here.
6. Release boot is not multi-machine acceptance. Separately run the planned named-node/cookie/network setup across actual machines, with trusted-network distribution and configured executor-local CA/workspace/credential resources. No automatic clustering, durable recovery, or retry should be inferred from successful assembly.

## 6. Validation record and remaining work

**Performed:** current-task resolution (no pointer; supplied task verified planning); repository/spec inspection; version-tagged primary-source/page-local extraction; actual Req Hex tarball checksum and five shipped-source equality checks; installed Elixir/OTP version probe; read-only file descriptor/stat/16-byte read probe; git-status inspection. Network reads were public documentation/source/package downloads only, kept in memory.

**Not performed:** `mix deps.get`, project compilation/tests, Req runtime/TLS/socket tests, mutation/race filesystem fixtures, release assembly/boot, real model requests, or true multi-machine acceptance. These would either mutate outside the sole permitted research artifact or require future implementation/explicit live resources. The direct OpenAI create page and an attempted OTP documentation-path URL returned 403/404 respectively; the official guide/pinned SDK and OTP source were used instead.

**Remaining technical gates:** actual transitive lock/version compatibility (especially Finch timeouts and Mint CA behavior); overflow/error-path tests; provider profile wire compatibility and strict validation subset; filesystem provisioning/TOCTOU caveat tests and deployment documentation; web conditional fail-fast tests and backend release closure/boot; later real-machine integration. No blocker requiring a new product choice was found within the proposed trusted-filesystem, non-streaming-first, no-web/no-retry plan; these detailed boundaries await final parent-plan review.

**Unexpected shared-index observation:** initial `git status --porcelain` showed the task PRD as `AM` and no research file; the final status showed the PRD as `A` and this report as staged `A`. This worker issued no index-writing command and changed only this report. External/shared tooling or another process apparently staged changes during the session. The supervisor was notified; no compensating index mutation was attempted. This note may itself remain unstaged. Initial task resolution exit 1 is expected metadata evidence, not a passed active-task lookup; subsequent research used the explicitly assigned existing task.
