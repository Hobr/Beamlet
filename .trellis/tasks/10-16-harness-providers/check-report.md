# Independent child-2 check report

Result: scoped Harness acceptance passes after repairs. No unresolved implementation
blocker remains. Parent integration, active LSP coverage and deployment/live-provider
evidence are explicitly separate below. Review covered complete source and tests,
including untracked files, not only git's tracked diff or implementation test claims.
The reviewer was the sole source writer; Actions/Runtime/planning/spec changes were
preserved. No index, task-state, root manifest, config, commit or archive mutation.

## Findings and disposition

| Finding | Disposition and regression evidence |
| --- | --- |
| Catalogue keys could differ from descriptor names, advertising one name while authorizing another. Malformed catalogue values could raise in batch/normalization. | Fixed by Catalogue.validate/1 using canonical reconstruction/equality; used for requests, replies and batches. Invalid native maps and mismatched keys tested. No call can be returned from an invalid batch. |
| Deterministic model bypassed complete history/request validation and could crash on missing fields/settings. | Shared validate_request/1 validates exact request keys, canonical catalogue, bounded messages and complete ordered result pairs; deterministic missing settings returns invalid_profile. Shared malformed-history cases tested. |
| Native request bounds omitted catalogue plus history together; normalization did not cap full incoming envelope for direct deterministic callers. | Full native request and incoming reply envelope capped at 1 MiB, as well as HTTP wire request/response and normalized reply. Oversized combined context/catalogue regression added. |
| Unknown profile/request fields were silently ignored; response choice/envelope action fields were also silently dropped. | Exact supported profile/request/envelope/choice keys enforced. Socket tests cover invalid request/action/configuration and semantic replies; harmless unknown metadata is conservatively rejected. Supported top-level metadata is allowed but not retained; assistant metadata retained exactly within supported keys. |
| Req.post(url, options) inherits global Req defaults/plugins, permitting unexpected adapters/parameters. | Fresh Req.Request.new plus pinned Req.Steps.attach avoids global defaults. Real socket regression installs a throwing global plugin and injected query parameters; neither takes effect. Explicit retry/redirect/raw/identity/TLS controls retained. |
| Argument string lengths counted graphemes despite documented codepoint bound; combining marks could bypass text limits. Additional-properties native maps accepted atom keys. | Count codepoints; reject non-string argument keys. Combining-mark echo and atom-key schema regressions added. |
| Truncation accepted an incomplete retained codepoint even when the sentinel already proved invalidity. OTP can classify an invalid short sequence as incomplete. | Check observed max+1 bytes and validate possible completion, including overlong/surrogate/range restrictions. Invalid observed continuations fail, genuinely incomplete truncated suffix is dropped. Tests cover 2/3/4-byte codepoints at every split, invalid sentinel and incomplete EOF. |
| Context.append malformed values had no error clause; progress serialization used a raising encoder. | append returns context_limit for malformed lists; invalid/unencodable progress returns progress_limit when a callback is installed. Hook functions themselves remain trusted local caller code. |

Eight new tests plus stronger original assertions; final independent count 26.
Existing whole-batch tests preserve opaque IDs/original order, reject duplicate and
missing/incomplete sibling calls before returning any batch, and validate the
registered shallow schema. Catalogue performs no dispatch or module resolution.

## Acceptance comparison

| Criterion | Independent evidence and boundary |
| --- | --- |
| Child AC1 / parent R1 and AC1 Harness portion | Independent child mix test: 26 passed. Direct Req/Jason only, no Actions/Runtime/Agent/Phoenix/Plug dependency/import. xref: zero cycles. Descriptors build without key/root/process. Environment is an opaque data struct, not placement authorization. |
| Child AC2 / parent R4 and AC5 | Actual TCP fixture checks POST /v1/chat/completions, bearer fixture auth, identity, configured model, JSON messages/tools/n=1/stream=false and opaque IDs. Socket semantic tests reject refusal/length/duplicate/malformed sibling/missing choice; pure normalization also tests content_filter/legacy/unsupported actions. 302/307/429/500/timeout each observes no second connection. Operator-only live smoke path documented in handoff, not run. |
| Child AC3 / parent R7 | Raw all-status synchronous callback, explicit overflow marker/halt, 1 MiB body bounds, encoding rejection and bounded normalized/native envelopes inspected. Socket oversize success/error/chunked bodies begin with valid JSON to catch partial acceptance. Invalid JSON/UTF-8 fail. Handshake-close and self-signed certificate fail without second connection/fallback. No parser-depth/header/transport-chunk/RSS guarantee. |
| Child AC4 / parent R4 and AC6 native portion | Dedicated-tree root ancestors, absolute/traversal/NUL/backslash/empty/depth/size paths, symlink roots/ancestors/leaves, directory/FIFO/device/missing leaves rejected before reads. Regular raw FD stat checks inode/device; max+1 read closes in after. Valid/empty/long UTF-8, every split width, invalid/incomplete retained text, explicit text/bytes/truncated metadata and repeated failure /proc/self/fd equality tested. No shell/write path. Eligibility/remote placement belongs to child 3, not established by these local tests. |
| Child AC5 | Handoff documents strict Chat Completions/schema/configuration subset, read-only trusted-tree assumption, TOCTOU/hardlink/mount/backing-writer/storage limitations and outer cancellation responsibility. Optional generation controls/custom CA absent; unsupported config is rejected explicitly. No material API/scope expansion. |
| Parent AC12 relevant checks | Final independent/umbrella tests, compile, format, strict Credo, checked-PLT Dialyzer, dependency/lock/xref review and whitespace checks passed. Four unchanged Runtime distributed tests excluded; active LSP unavailable. Full parent integration/release/physical-host gates remain parent-owned. |

Profile-controlled optional generation parameters are permitted by parent design,
not required for every compatible model. The fixed standard text/function request
satisfies the approved minimal subset. Models requiring max_completion_tokens,
temperature or other options are unsupported until a reviewed profile extension;
unknown keys now fail rather than creating misleading configuration. No custom CA
option or arbitrary transport override was added. Exact Req 0.7.5/direct Jason
remain declared; lock contains only five required additions and no upgrades.
Resolved Finch 0.24.0 and Mint 1.11.0 source behavior and locked package status were
inspected. Low-level Req.Steps usage is deliberately coupled to the exact Req pin.

## Verification and remaining evidence

Final exact commands/counts and resolved failures are recorded in verification.md.
Independent Harness: 26 passed, no skips. Umbrella: 66 passed plus four excluded
Runtime distributed tests. Compile warnings-as-errors, umbrella format, strict
scoped Credo (69 checks), Dialyzer (checked current PLT, zero errors/skips), all nine
Harness dependencies, xref and git diff whitespace checks pass. Index is empty.
Expected fixture TLS notices contain certificate failure metadata only; Runtime
fault-injection logs and Web request logs belong to existing sibling tests.

No active LSP tool is exposed and prior caches contain no Harness coverage. This
is unavailable diagnostic evidence, never a clean LSP result. No paid call,
physical-machine, release or distributed-peer rerun was performed. Existing
Runtime protocol was unchanged; no new peer integration reason was found.

Cancellation hooks are local pre-invocation checks; they do not poll during HTTP
or file IO. Outer Runtime/Agent adapters own operation deadlines, termination and
progress credit. Socket timeout/no-retry evidence does not prove upstream request
cancellation, non-acceptance or absence of billing. Native malformed callback
functions/exceptions are caller errors, not provider data. Context.append bounds
without eviction; validate_request checks full tool/result history before a model
runs. Context never selectively removes a pair.

Residual limitations: trusted dedicated local tree required; lstat/open TOCTOU,
raced special-file opens before fstat, hardlinks, mounts, malicious/backing writers,
non-snapshot reads and failing storage latency are not contained. max+1 validates
only observed bytes; omitted suffix is not scanned. Retained body/envelope caps
are not hard memory or JSON-depth limits. Provider compatibility is the declared
subset; remote eligibility, runtime cancellation integration and product release
remain later-child evidence. No unresolved blocker within the reviewed child scope.
