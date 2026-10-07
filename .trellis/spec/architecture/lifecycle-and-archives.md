# Lifecycle, Continuation and Portable Archives

Status: reviewed target contracts. ETF resource limits and code compatibility require runtime prototype validation.

## 1. Scope / Trigger

Own suspend/resume, stable-boundary fork, portable import/export, versioned data and the DTO/codec boundary. A live process, mailbox, external filesystem or provider credential is not a portable computation snapshot.

## 2. Signatures

~~~text
Beamlet.suspend(run_ref, command_id: key, ...)
Beamlet.resume(run_ref, command_id: key, ...)
Beamlet.move(run_ref, target_host_ref, command_id: key, ...)
Beamlet.fork(run_ref, boundary_ref, command_id: key, ...)
Beamlet.export(run_ref, boundary_ref, profile, ...)
Beamlet.import_archive(binary, bindings, profile, command_id: key, ...)

PortableData.encode(term, profile) -> {:ok, binary} | error
PortableData.decode(binary, profile, registered_schema) -> {:ok, term} | error
~~~

Mutations use the receipt/error contract in [Computation and Effects](./computation-and-effects.md). Decoder/encoder names are target interfaces, not implemented modules.

## 3. Contracts

### Suspension and Continuation

After committed suspension, no new state advancement or attempt admission succeeds. Grants ordered before it remain admitted; they may start later, finish, and record outcomes while suspended.

Resume obtains fresh advancement permission, reloads state/input/progress and consumes committed outcomes. It never repeats a completed operation just because a process restarted.

Ready state has a data-only continuation keyed by Run/state revision. Original resume consumes that committed input. A new branch reconstructs its own continuation; it never imports a PID/closure or executable source queue. Waiting needs new ordinary input; finished remains terminal.

Stable-boundary eligibility is recorded at its commit: no pending/executing/unknown Effects in the snapshot's causal work and no unconsumed canonical replies. Later completion cannot retroactively make an earlier in-flight checkpoint stable. Stability does not prove physical quiescence of resources/older attempts.

### Branch Identity and Archive

Fork copies application state and the selected completed history prefix. Source execution continues independently. New Run identity makes subsequent Effect identities distinct; inherited history is read-only.

Branches are initially suspended. Pending source external-input queues and running attempts are not activated. Referenced child Runs/resources remain references; recursive graph/environment copying is an explicit application composition.

| Archive manifest field | Contract |
|---|---|
| format_version | Positive supported version, initially 1 |
| codec_profile | Registered data profile ID/version |
| origin | Authority-domain/Run/boundary identities and provenance information |
| definition_ref | Registered logic/state/input versions |
| snapshot | State, state revision, source input cursor, progress and Scope descriptor |
| history | Necessary prefix, completed outcomes and lineage; no executable source queue |
| resource_requirements | Logical identities/versions/constraints to satisfy at target |
| integrity | Optional recorded-byte integrity information; not proof of external truth or authorization |

Import validates the archive and resolves code/resources before activation. It creates a suspended new branch with a keyed receipt; explicit resume activates it. A source input cursor remains origin metadata, not permission to consume a new branch's queue.

Include required immutable payload data or use a verified durable reference. Missing data/resources/code produces an explicit non-executing outcome. Import does not install code, copy credentials, delete the source, or restore external effects.

Code/hot upgrades do not silently migrate old state or reinterpret operations. Use matching registered versions or declared compatible targets. A future migration is explicit/versioned and preserves the original history.

### ETF Profile

The initial target profile is etf-data-v1: standard, uncompressed OTP ETF with application validation.

Supported data: integers/floats, binaries/bitstrings, proper lists, tuples, maps, and approved existing atoms. Registered structs are validated maps with approved tags/schema. External names use binaries.

Recursively exclude PIDs, ports, references, functions/closures. Persist stable logical references instead. The encoder never uses the instance-local option. Neither encoding success nor :safe decoding proves application validity.

Required positive profile configuration:

| Key | Meaning |
|---|---|
| max_record_bytes | Encoded record ceiling |
| max_archive_bytes | Import/export byte ceiling |
| max_term_depth | Decoded structure depth ceiling |
| max_term_nodes | Decoded structure/count budget |
| decode_timeout_ms | Supervised decoder time guardrail |
| decoder_heap_words | Worker heap guardrail |

These are required bounded settings, not claimed production defaults. Measurements establish role/application defaults; startup/import rejects missing or unbounded profiles. Worker limits are guardrails, not a hostile-code sandbox or hard RSS guarantee.

Import applies byte limits before decode, rejects compressed/top-level instance-local wrappers for this profile, then uses safe + used decoding, full-byte consumption, recursive data validation and registered schema checks. Normalize accepted logical data through standard encoding before retention/export. No complete custom ETF parser or serializer registry is needed.

Encoding/normalization happens at the serialization boundary before conditional store commands. Replicas apply captured data rather than derive identities from their own re-encoding, clocks or randomness.

Record digests identify their byte/profile/version scheme. Cross-OTP logical equality cannot assume universal canonical ETF bytes. Permission/provenance validation remains separate from checksum/decoding.

Providers respect declared response bounds or supply verified data references. Oversized or malformed results are not silently truncated; an external operation with an unrecorded result remains uncertain.

## 4. Validation & Error Matrix

| Condition | Behavior |
|---|---|
| Suspension command/grant race | Authority commit order decides; no retroactive cancellation claim |
| Fork source has unsettled Effect/completion | not_stable |
| Missing source prefix/checkpoint data | invalid_archive/unavailable_data |
| Unsupported format/profile/schema/code | incompatible_version; no activation |
| Unsatisfied target resource/permission | unavailable_resource/forbidden; no execution |
| Nonportable term, malformed/trailing bytes | invalid_data |
| Oversize/deep/too many terms or decoder guardrail exceeded | resource_limit |
| Unknown atom requires creation/code installation | Reject safely; never auto-create/load |
| Compressed/local wrapper not admitted by profile | unsupported_encoding |
| Existing import key with changed logical archive/bindings | key_conflict |

## 5. Good / Base / Bad Cases

Good: an object-processing Run records read data, commits ready state, exports that stable point, imports a suspended new branch, validates bindings and resumes with a new write invocation.

Base: export/import a waiting Agent turn boundary; the imported branch waits for a new user input.

Bad: restore an old PID, decode arbitrary functions, repeat completed prefix actions, clone pending source input/attempt queues, or silently choose a different model/resource.

## 6. Tests Required

<a id="s5"></a>
### S5 — Lifecycle Coverage

Trace movement, suspension, resume, review, stable fork and archive/import with pending and completed work. Verify recorded definition/configuration version interpretation and explicit incompatibility behavior.

<a id="s13"></a>
### S13 — Stable Fork and Identity

Source head has outstanding work; fork an earlier recorded stable point. Assert prefix/state preservation, independent new identity, source continuation, no historical execution and no copied live queue. Reject an in-flight/unconsumed-completion checkpoint.

<a id="s17"></a>
### S17 — Portable Activation

Round-trip stable ready/waiting/finished snapshots to a compatible target domain. New branches start suspended; ready recreates a fresh data continuation, waiting receives new input, finished stays terminal. Missing code/schema/resource data blocks execution without implicit installation or source mutation.

<a id="s18"></a>
### S18 — ETF Boundary

Round-trip every supported category. Reject nested live handles/functions, malformed/trailing data, unsupported encodings, unknown-schema/atom creation and every configured size/structure guardrail. Compare logical values across supported toolchains without relying on canonical byte equality. The runtime prototype must measure decoder resource behavior.

<a id="s19"></a>
### S19 — Suspend/Admission Race and Retained Reply

Commit suspension before/after attempted grants and step proposals. Assert all later grants/advancement fail, previously admitted completion can commit, restart retains it, and resume consumes it once. No external-cancellation assertion is allowed.

## 7. Wrong vs Correct

~~~text
Wrong: :sys.suspend(pid) is the durable suspension contract.
Correct: commit control mode/epoch; reconstruct actors and retain authority outcomes.

Wrong: binary_to_term(bytes) -> start archive-provided module.
Correct: bound -> supervised safe/used decode -> validate data/schema/registry/resources -> new suspended branch.

Wrong: deserialize a source continuation function or copy its inbox.
Correct: restore progress data and create a fresh branch-local continuation.
~~~
