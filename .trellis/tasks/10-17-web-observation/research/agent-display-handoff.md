# Stage A — Agent display handoff

Stage A is implemented and locally verified. Stage B Runtime/Node observation and independent whole-child acceptance remain outstanding. Do not mark the observation child accepted. No commit, staging, branch, archive, task-pointer, dependency/config, shared-spec or out-of-bound source changes were made.

## Changes and ownership

Preserved and inspected the interrupted tracked diff and all three untracked source/test files before editing. The complete stage diff consists of:

- `apps/beamlet_agent/lib/beamlet/agent.ex`: additive display snapshot/subscription overloads.
- `apps/beamlet_agent/lib/beamlet/agent/server.ex`: optional metadata validation, source entry annotations, view-specific publication through existing credits, and actual observed child identities.
- `apps/beamlet_agent/lib/beamlet/agent/delegation.ex`: notify parent after actual child Ref/input turn/subscription have been obtained.
- `apps/beamlet_agent/lib/beamlet/agent/display.ex` (untracked): bounded projection and metadata validation.
- `apps/beamlet_agent/test/beamlet/agent/display_test.exs` (untracked): nine deterministic integration tests.
- `apps/beamlet_agent/test/beamlet/agent/display_projection_test.exs` (untracked): six projection tests.

This resumption changed only Display and DisplayProjectionTest within those six files. It fixed prepared sibling tool calls being projected as admitting before actual dispatch ownership existed. Projection now requires an owner for that call/current turn, a pending operation, or a result. A regression test covers prepared-only calls and stale-turn owners. The prior implementation otherwise remained intact.

Server remains the state owner. `display_entries` contains only `%{id: reference, turn: reference}` aligned with the existing neutral messages; no second transcript. Current Context.append rejects overflow rather than evicting context: at most128 messages/1MiB neutral JSON. Annotation references are allocated when accepted messages are appended, remain stable across reads/turns, and disappear with the Agent incarnation. Private immutable binding, messages and model requests are unchanged. Activities derive from actual owners, pending operations, assistant calls/results and children. No coordinator-private inspection, persistence, replay, Web dependency, new service or model/tool dispatch on reads.

## Public API and metadata

```elixir
Beamlet.Agent.snapshot(ref, view: :display)
Beamlet.Agent.subscribe(ref, sink, view: :display)
```

Return/envelope/Ref/sequence semantics remain the existing ones. `snapshot/1` and `subscribe/1,2` keep their default seven-field snapshot. Explicit empty option lists also use default view. Unsupported options return `{:error, :invalid_command}`. Subscription is one view per sink, at most32 sinks/16 outstanding snapshots each. Sink itself calls existing ack/2; dirty snapshots coalesce into a replacement. Sink DOWN removes observation only. No history/delta semantics. Stale incarnation and dead Ref errors remain existing errors; command reads use existing finite5s handling budget. Identity list/lookup still uses the existing isolated identity path.

Optional creation `display_metadata` defaults to `%{}`. Plain atom-key maps only:

- `title`: optional nonempty UTF-8 text, <=128 bytes.
- `preset_id`: optional nonempty UTF-8 public ID, <=128 bytes.
- `option_ids`: optional plain map permitting `model`, `environment`, `constraints` as single nonempty UTF-8 IDs <=128 bytes, and `tools` as a proper list of at most64 distinct such IDs.
- Complete metadata <=4096 Erlang serialized bytes, inclusive. Unknown keys, structs, improper lists, duplicate tool IDs, invalid UTF-8, wrong types and excess sizes reject as `invalid_agent_options`.

These are trusted public descriptions, not executable configuration or authorization. Names/modules, model binding/config/credentials and tool root settings are not projected. Text supplied by trusted caller/provider/tool can echo sensitive content; no malicious-echo filtering or secret erasure guarantee. Consumers must render text escaped and untrusted.

## Display version1 schema and limits

Normal display is `%{version: 1, coverage: :live_context, metadata: map, entries: list, activities: list, omitted: %{entries: count, activities: count}, truncated: boolean, reasons: atoms}` added to the base snapshot.

Entries carry source `id`/`turn`, neutral `role`, bounded `content`, `call_id`, `calls` and `truncated`. Calls carry neutral ID/name and bounded JSON-text `arguments` plus `truncated`. Entry IDs are opaque incarnation-local references, not durable cursors. Turns come from source acceptance/append; continuation child observations use the delegation turn. Assistant calls are retained as neutral history only when the batch observations are appended, consistent with existing model history.

Activities share `kind`, `id`, source `turn`, `status`, `placement: :unknown`, `truncated`. Model activity includes observed operation/attempt when available; admitting means an actual operation owner exists. Tool activity includes name/arguments/result and observed operation/attempt when available. `:pending` means a Runtime Ref was received, not proof an executor has begun work. Child activity includes actual observed child Ref/child_turn, or starting with nil identities until observed; interim completed child results are bounded JSON text. Safe non-JSON child terminal values are explicitly omitted (`result_omitted: :unsupported_content`), never inspected into text. Terminal activities disappear; this is current activity, not an event timeline.

Limits: most recent32 entries; at most16 current activities; each content/argument/result text <=8192 UTF-8 bytes with codepoint-safe truncation; full display target <=131072 serialized bytes. Existing conservative1048000-byte complete subscription-envelope budget also applies to display additions. Reasons include entry_limit/activity_limit/field_limit/unsupported_content/snapshot_budget; omitted counts include entries/activities removed by byte pressure. Fitting removes oldest displayed entries, then activities, then metadata. Under extreme pressure only `%{version: 1, coverage: :live_context, truncated: true, reason: :snapshot_budget}` may remain; if even that cannot fit, return the original base snapshot without display. Requested-view absence is complete omission and must replace any prior display. Default snapshots valid under the old map budget stay valid; base final/progress are never shrunk to fit display, even when old map-only accounting left insufficient envelope room. Projection never modifies source/model history.

## Current validation evidence

All commands ran from `/mnt/data/Project/Beamlet`. Logs retained under `/tmp`; no prior failure log overwritten. Final edits precede these final checks:

- `mix test apps/beamlet_agent/test apps/beamlet_cli/test --seed 631927`: Agent26 passed; CLI18 passed,1 distributed excluded. `/tmp/agent-display-resume-gate-tests.log`.
- `mix test apps/beamlet_runtime/test apps/beamlet_node/test --seed 631927`: Runtime30 passed,6 distributed excluded; Node60 passed,16 distributed excluded. `/tmp/agent-display-resume-gate-neighbors.log`.
- Total final suites:134 executed/passed,23 distributed excluded. Default tag configuration excluded those tests; these are ordinary local suites, not named-peer evidence.
- `mix format --check-formatted`: exit0, `/tmp/agent-display-resume-gate-format.log`.
- `mix compile --warnings-as-errors`: exit0, `/tmp/agent-display-resume-gate-compile.log`.
- `mix credo apps/beamlet_agent --strict`: exit0;18 files,233 mods/functions,69 checks, no issues. `/tmp/agent-display-resume-gate-credo.log`.
- `python3 /tmp/agent-display-resume-gate-lsp/probe.py`: active didOpen probe for agent.ex/server.ex/display.ex/delegation.ex; all four received publishDiagnostics with empty diagnostics after final edits. Probe disables LSP Dialyzer. Output/results/transcript/stderr in `/tmp/agent-display-resume-gate-lsp/`.
- `git diff --check`: passed. `git diff --cached --name-only`: empty; no staged files.

Coverage includes real deterministic two-turn model/two concurrent tools with reversed completion, large structured results, immutable binding and full neutral requests, actual child refs and continuation annotations; exact4096/4097 metadata and UTF-8 limits; exact8192/8193 text and JSON bounds, all UTF-8 split widths, entry/activity/aggregate/full-envelope pressure without source mutation; malformed/private metadata and invalid view options; mixed sinks,16-credit exhaustion, ack identity, replacement coalescing, sink death; stale turns/Refs, stop, owner loss, suspended read and identity-island replacement. Existing Agent/Node regression suites retain portable-child validation and bounded owner-retirement coverage.

## Runtime diagnostic and preserved failed attempts

Original failure remains `/tmp/agent-display-regression-final.log`: seed631927 RuntimeCompositionTest at composition_test.exs:23, assertion line31; no success message after100ms, empty mailbox. That output contains no later terminal result, coordinator state or timing trace, so original cause cannot be inferred. Do not call this a pre-existing flake.

Resumption `mix test apps/beamlet_runtime/test/beamlet/composition_test.exs --seed 631927` passed2 (`/tmp/agent-display-resume-runtime-focused.log`). The first repeated full four-app regression passed Runtime30/Agent25/Node60/CLI18 before the resumption fix (`/tmp/agent-display-resume-regression.log`). Runtime also passed30 during the later candidate regression and final neighbor run. Classification: historical100ms receive failure currently unreproduced; root cause unresolved. Neighbor inspection confirms TestPeer.barrier waits for Directory eligibility before one submission, not final execution completion. This alone does not prove scheduling delay, capacity staleness or Agent causality. No Runtime changes, assertion weakening or business retries were introduced. Supervisor was informed of the unresolved diagnosis.

The initial tool-ownership fix mistakenly used nil-valued comprehension assignments as filters: candidate four-app run failed3 Agent tests (23/26 Agent passed; all neighbor/CLI tests passed). Preserved `/tmp/agent-display-resume-final-regression.log`. Corrected to singleton generators; Agent26/CLI18 then passed (`/tmp/agent-display-resume-corrected-regression.log`). Strict Credo subsequently found complexity10 in tool_activities; preserved `/tmp/agent-display-resume-final-credo.log`. Extracted the activity predicate and final scoped Credo passed. Earlier comma/repeated `--files-included` commands inspected110 umbrella files rather than the intended scope; final positional app path inspected18 Agent files. Earlier LSP/format/compile outputs exist but are superseded by gate evidence above.

## Remaining work and risks

- Historical Runtime failure has no proved root cause despite successful current reproductions; retain it for independent acceptance.
- Stage B Runtime/Node observation is not implemented here. Whole-child independent check, shared-spec updates, named distributed suites, Dialyzer and full umbrella/release checks were not run in this Stage A resumption and remain later gates as applicable. No physical-host, paid/live provider or deployment claim.
- Display replacement can omit all display under old base-budget pressure; clients must handle this explicitly. Coverage is only retained live context and current/coalesced activity, never complete history.
- No model/provider fallback or alternate CLI workaround was used. Source/tests stay uncommitted and untracked new files must be included by the eventual parent commit.
