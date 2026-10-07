# Computation, Invocation and Effect Contracts

Status: reviewed target contracts; signatures and payloads are for future implementation.

## 1. Scope / Trigger

Own the business-facing transition, reference identities, shared record schemas and generic public interfaces. Authority transitions are defined in [Authority and Recovery](./authority-and-recovery.md).

## 2. Signatures

Target definition result:

~~~elixir
@callback step(portable_term(), application_input()) ::
  {:continue, portable_term()}
  | {:wait, portable_term()}
  | {:invoke, portable_term(), nonempty_list(invocation())}
  | {:finish, portable_term(), portable_term()}
~~~

Application input is :continue, {:external, data}, or {:reply, reply_key, invocation_ref, {:ok, data} | {:error, data} | {:unknown, evidence}}. The durable input envelope/cursor is handled outside the business definition.

Target facade operations:

~~~text
Beamlet.start_run(definition_ref, initial_state, scope_descriptor, opts)
Beamlet.submit_input(run_ref, input, opts)
Beamlet.suspend(run_ref, opts)
Beamlet.resume(run_ref, opts)
Beamlet.move(run_ref, host_ref, opts)
Beamlet.inspect_run(run_ref, query)
Beamlet.fork(run_ref, boundary_ref, opts)
Beamlet.export(run_ref, boundary_ref, profile, opts)
Beamlet.import_archive(binary, bindings, profile, opts)
Beamlet.resolve_invocation(run_ref, invocation_ref, decision, opts)
~~~

Mutating calls return {:ok, receipt} or {:error, error}. Export returns {:ok, binary}; inspection returns {:ok, projection}. Errors always contain a stable code and bounded details. commit_unknown means a command may have committed.

## 3. Contracts

All references are opaque portable data, never PIDs. Callers must not parse them or equate InvocationRef with internal EffectRef.

| Record | Required fields / constraints |
|---|---|
| DefinitionRef | id and logic_version: binary; state_schema and input_schema: registered name/version references |
| RunRef | authority-domain and Run identities; internal encoding is opaque |
| Invocation | operation_ref: capability/operation/version; arguments: portable term; reply_key: binary or approved static atom; resource_constraints: validated data |
| Reply | reply_key, invocation_ref, result; no Effect/Attempt/store object |
| InputEnvelope | stable input_id, positive queue_seq, kind, application payload, provenance; queue/cursor is internal |
| Run snapshot | definition_ref, state, state_revision, input_cursor, progress, scope_descriptor, mode, lifetime |
| Effect intent | effect_ref, originating Run/step/call ordinal, Invocation, effective configuration, captured repeatability declaration |
| Attempt | attempt_ref, effect_ref, provider/resource/generation binding, original admission evidence |
| Receipt | command_id, run_ref, history_revision, state_revision where applicable, operation result |
| Error | code: stable atom/binary; details: bounded portable data; no leaked live objects |

Reference/version names from external sources are binaries. Registered code is resolved from trusted configuration, never archive-supplied MFA.

Mutating opts require a stable command_id allocated once per logical request. Input append also requires a stable input key. Retries retain the original logical payload. Same key with different normalized data fails key_conflict.

### Progress and lifecycle

Mode is active or suspended. Lifetime is open, finished or failed. The application's phase remains opaque state.

| Step result | Committed progress | Behavior |
|---|---|---|
| continue | ready | Commit a data continuation keyed by Run/state revision |
| wait | waiting | Await ordinary external/reply inputs |
| invoke | waiting | Atomically create a nonempty invocation set as Effects |
| finish | finished | Close admission only after relevant completions are settled |

An obsolete internal continuation is dispositioned without evaluating against a newer revision. Imported/forked ready state reconstructs a fresh branch-local continuation; original resume uses its committed one. A finished checkpoint does not silently restart.

Effect state is pending, executing, unknown, outcome_recorded or consumed. Executing denotes an admitted attempt, not physical start. Attempt state is admitted, unknown or observation_recorded; evidence/result are separate.

Finishing preserves explicit not-processed dispositions for remaining external inputs. Acceptance never implies successful processing. Unsettled Effect completions cannot be silently discarded.

### Identity and capture

Proposed internal Effect allocation: Run identity + committed step sequence + invocation ordinal. Attempts add an authority ordinal; ownership epoch is not logical identity.

Host movement keeps identities. New branches obtain new Run identity for subsequent Effects. Completed inherited history remains read-only.

Capability facades build data without I/O. Transitions avoid clocks/randomness/mailboxes/live resource reads; obtain observations through capabilities. Uncommitted transitions may be re-evaluated. Normalize/capture effective configuration before authoritative creation; persisted intent remains immutable.

## 4. Validation & Error Matrix

| Condition | Code / behavior |
|---|---|
| Invalid/nonportable state/input/arguments/result | invalid_data; no false receipt |
| Unregistered/incompatible code/schema | incompatible_version |
| Changed data under same command/input key | key_conflict |
| Old revision/ownership permission | stale_permission |
| No required resource | unavailable_resource; preserve request meaning |
| No valid authority path before submission | authority_unavailable |
| Submitted mutation has no established commit outcome | commit_unknown; query/retry original key |
| Nonstable boundary | not_stable |
| Finish with unsettled completions | invalid_transition; preserve state/work |
| Input submitted to finished Run | run_finished |

An uncertainty notice is an ordinary durable Reply/input without a terminal canonical result. Consuming it does not settle the Effect. Resolution records evidence or explicit repeat permission through the invocation reference; it never rewrites original intent/history.

Inspection uses revision-bearing bounded pagination. A snapshot query and a history/attempt query return typed projections, not backend files. Rendering consumers do not independently decode ledger payloads.

## 5. Good / Base / Bad Cases

Good: Agent settings create a normal Invocation, whose committed Reply updates ordinary Agent state. A subagent provider uses keyed generic Run creation.

Base: create an initial ready snapshot; :continue produces the first invocation.

Bad: a pure transition calls a provider directly, creates fresh retry IDs, or treats unknown as a known terminal failure.

## 6. Tests Required

<a id="s2"></a>
### S2 — Explicit Progress and Restart

Assert that state/input consumption/new Effects or continuation share one commit. Lose a proposal before commit and re-evaluate without external execution. Restart a ready/waiting snapshot and preserve the correct directive/cursor. An Agent definition receives ordinary replies only.

Verify same-key/same-payload creation and input deduplication, changed-key payload conflicts, duplicate continuation suppression and explicit terminal-input disposition. A duplicate committed reply must not advance state twice.

## 7. Wrong vs Correct

~~~elixir
# Wrong: provider I/O during a replayable transition.
response = HTTPProvider.request(arguments)

# Correct contract: the facade returns Invocation data.
call = LLM.chat_call(arguments, reply_key: :chat)
{:invoke, next_state, [call]}
~~~

The facade in the example is a target declaration interface. It does not imply an implemented HTTP/LLM module.
