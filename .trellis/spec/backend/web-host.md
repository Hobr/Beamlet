# Web Host and Preset Adapters

## 1. Scope / Trigger

Use for Web startup, preset selection, creation callers and temporary navigation.
Sources: `apps/beamlet_app_web/lib/beamlet_web/{host,presets,agents,handles}.ex`,
`host/bootstrap.ex`, and the complete operator schema in `apps/beamlet_app_web/HOST.md`.
This is the implemented adapter layer; workbench/management UI remain separate.
Core libraries have no Phoenix dependency. No database, transcript, replay or
online catalogue mutation is provided.

## 2. Signatures

```elixir
{:ok, config} = Beamlet.Web.Host.configuration(settings)
public = Beamlet.Web.Presets.describe()
{:ok, draft} = Beamlet.Web.Presets.reset(preset_id)
{:ok, private_resolution} = Beamlet.Web.Presets.resolve(draft) # server only
outcome = Beamlet.Web.Agents.create(draft)
input_outcome = Beamlet.Web.Agents.input(ref, text)
{:ok, handle} = Beamlet.Web.Agents.attach(exact_descriptor)
{:ok, ref} = Beamlet.Web.Handles.fetch(handle)
```

## 3. Contracts

Startup-only `config :beamlet_app_web, :host, settings` is a unique-key keyword list:
`enabled` defaults false, `node` defaults `[roles: [:interaction]]`, `allowed_nodes`
and `peers` default empty, `catalogue` defaults empty. Unknown/duplicate keys reject.
Node validates its options; roles must include interaction. Ordinary loading starts
an empty Host tree and performs no network/provider work. Explicit enabled Host
owns one Node per VM. Keep server/CLI hosts disabled in that VM.

Application supervises Host separately from Telemetry/PubSub/Endpoint. Enabled Host
uses rest_for_one ordered Node, Presets, Handles, temporary Bootstrap. Navigation
loss cannot restart earlier Node; Node loss clears later navigation. Host/Web loss
can lose embedded authority Agents; remote surviving Agents can be rediscovered.
Bootstrap connects distinct configured peers once, sequentially, through Cluster,
max32 trusted names, each attempt with5s helper budget. Host loss retires helpers;
an initiated OTP handshake may finish later. Browser operations never connect.

Catalogue is a strict atom-key map of models/tools/environments/presets/authorities
and default_authority. Entries are maps keyed by public string IDs. Bounds:32 each
except64 tools. IDs/titles are nonempty valid UTF-8 <=128 bytes; descriptions<=2048.
Every entry has title/optional description. Model has private binding; Tool has
portable route without environment, neutral descriptor and allowed public environment
IDs; environment has opaque core value; preset has model/tools/optional environment;
authority has target `:local` or a trusted allowed name. Model validators reuse the
trusted provider registry; no provider IO/key-env fallback. Tool descriptor names
are globally unique. Executor settings/roots remain in Node profiles. Full exact
schema and opt-in deterministic example are linked from HOST.md, not auto-imported.

Public describe returns labels, preset references, Tool environment choices and
default authority, never binding/config/credentials/target names. Draft has string
keys preset/model/tools/environment/authority/title/task; task<=65536 UTF-8 bytes.
Tool IDs are distinct<=64. Reset returns a fresh draft. Environment is only required
by selected Tools and must be compatible with all requiring Tools. Resolve creates
matching tools/catalogue plus immutable binding and <=4096-byte display_metadata.
Resolved options stay server-only, outside browser-rendered state, session, URL and
logs. Trusted labels are provenance descriptions, not proof or secret sanitization.

Create sends one Agent.start, then one input after confirmed creation. Results:

- `{:rejected, :invalid_draft}` before start.
- `{:create_unknown, %{authority: atom, id: id}}` without confirmed Ref; static
  remote errors do not prove absence. Retain identity server-side for explicit discovery.
- `{:created, %{ref: ref, navigation: {:ok, handle} | {:error, reason}, input: outcome}}`.
  Confirmed Ref survives navigation failure and input rejection/uncertainty.

Input outcome is `{:accepted, turn}`, `{:rejected, reason}` for known busy/invalid
rejection, or `:input_unknown`. Never automatically retry creation/input or close
an instance after lost feedback. Remote start/input use existing5s erpc/control
calls; local DynamicSupervisor admission has no whole-call timeout. A create caller
can still be blocked after5s, and queued creation can run after its death. Presets
process absence exits the caller before start. Future LiveView must use owned
callers with finite UI deadlines, catch exits, lock duplicate clicks while pending,
and preserve uncertainty. Helper DOWN proves neither business rollback nor queue
retraction. Navigation remember/fetch normalize process-call exits to unavailable;
a timed-out handle insertion may complete later as bounded identity data.

Handles are32-character Base64url tokens from24 random bytes, max4096 entries and
one-hour idle expiry, with60s cleanup. Remember performs exact descriptor lookup;
fetch rechecks descriptor and complete Ref/incarnation. Same-name replacement never
rebinds. Mapping stores descriptor/Ref/touch time only and never owns/closes Agents.
Restart clears it. Handles are not authorization; shared exposure needs deployment
controls and any required per-user core authorization. Keep loopback development,
CSP/CSRF/origin/escaping and production secret checks.

## 4. Validation & Error Matrix

| Condition | Result |
| --- | --- |
| Invalid startup keys/roles/catalogue | invalid_web_host_configuration |
| Invalid standalone catalogue | invalid_web_catalogue |
| Unknown/duplicate/oversize draft IDs or raw binding/module/node fields | invalid_draft, no start |
| No confirmed creation acknowledgement | create_unknown, no resubmission |
| Confirmed create but navigation unavailable | created Ref retained, navigation error, one input |
| Confirmed create but input rejected/unknown | created Ref retained with separate input outcome |
| Missing Presets / blocked local admission | caller exit / no whole-call bound; owned UI deadline required |
| Missing/stalled Handles | unavailable; no business retry/closure |
| Invalid/expired/replaced handle | stale_handle |
| Handle capacity | handle_limit |

## 5. Good / Base / Bad Cases

Good: adjust public IDs, create once, retain confirmed Ref and display each outcome.
Base: deterministic no-Tool preset needs no environment. Bad: render a resolution,
retry uncertain start, or treat caller termination as cancellation.

## 6. Tests Required

Preserve actual four role trees, disabled isolation, named interaction-only remote
turn and bootstrap helper DOWN before suspended peer resume. Assert immutable
reset/source config, exact route/catalogue keys, conditional environments, byte/count
bounds and credential absence. Trace one start/one input, confirmed creation under
missing/stalled navigation, lost input acknowledgement and unknown remote creation.
Exercise stale descriptor/incarnation, idle/cap pressure, actual navigation death,
Agent survival and remote reattachment after Web restart. Local admission probes
must observe caller DOWN before resume and detect late-created idle Agent with no
input. Same-host named tests are not physical/provider acceptance.

The parent-level `all_role_journey_test.exs` composes one enabled interaction+authority+
executor Host with its own provider registry, Tool profile and allowlist, then drives
creation, a real executor Tool round-trip, a second turn and stop/leave/close through the
workbench. Preserve it; it is the only whole-Host journey gate.

Independent host/preset review passed25 ordinary/3 excluded,3 actual named/25
excluded and3 temporary boundary probes, plus format/warning-fatal compile/strict
Credo/Sobelow/existing-PLT Dialyzer (no refresh). Earlier244 ordinary and copied
release evidence belongs to an earlier candidate; do not extrapolate a new full
umbrella count. LSP timeout/unavailability is inconclusive.

## 7. Wrong vs Correct

Wrong: run local create in a LiveView callback and assume its deadline retracts it.
Correct: own a finite UI caller, retain ambiguous identity for discovery and never
resubmit automatically. Wrong: navigation error discards a confirmed Ref. Correct:
return navigation failure separately while preserving the created instance.
