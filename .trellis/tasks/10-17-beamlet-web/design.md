# Beamlet Web — Technical Design

## 1. Status and evidence

The user replied “批准” after the final planning summary on 2026-10-17, approving implementation in child-task order while retaining the explicit no-persistence/no-database boundary. The parent remains the integration owner; start with the observation child, not the parent. Existing behavior and source anchors are in [current capabilities](research/current-capabilities.md).

This parent owns product boundaries and integration acceptance. Four children deliver shared observation, Web host/presets, workbench and management. Ordering is observation + presets first, then workbench, then management and parent integration; see implement.md for conflicts and gates.

## 2. Composition and dependencies

Use existing Phoenix LiveView/HEEx/Tailwind/DaisyUI, not a separate SPA or new API server. Web adds direct umbrella dependencies on Node/Agent and only other libraries whose public APIs it actually calls; core libraries never depend on Phoenix, Web, daemon or CLI.

Proposed Web-owned modules live under `apps/beamlet_web/lib/beamlet_web/` with `Beamlet.Web.*` namespace:

- `Host`: validates opt-in composition configuration; disabled by default in ordinary app loading/tests. Enabled host explicitly supervises one Node, supports interaction-only and combined role subsets including interaction; Node itself still supports all seven subsets.
- `Presets`: immutable trusted startup catalogues and a pure browser-safe descriptor projection / server-side resolver. No database, user config upload, Elixir eval or dynamic module loading.
- `Agents`: small Web adapter over public Agent/Node calls; explicit create-then-input outcome handling.
- `Handles`: bounded VM-local map from random opaque browser handles to observed descriptors / Refs and safe display metadata. No process that owns Agent life. It is a navigation aid, not a transcript, auth system or durable identity store.
- `AgentLive` / new-agent LiveView, `Admin.*Live` and shared function components. Exact file splitting follows coherent feature boundaries, not a generic services/utils layer.

Web host config separates startup-only `node` options, trusted names/peers and public preset IDs from private model invocations/tool settings. Node option validation reuses Node.configuration. Daemon/CLI remain disabled; no competing fixed-name Node trees. Connect configured peers once in a supervised task after Node startup, never in HTTP mount or page refresh. Use Cluster for trusted names; no arbitrary connect textbox or automatic reconnect loop. Local non-distributed mode uses explicit `node()` local authority/list path; connected-remote aggregation retains the library contract.

Keep the existing endpoint available when the Web-owned host is disabled: an unconfigured state explains how to enable it without initiating work or fabricating sample Agents. Provide an explicit trusted deterministic example for local evaluation, not an automatically provisioned paid model/key.

## 3. Preset contract and creation flow

Trusted startup catalogues contain bounded public IDs and private resolved definitions:

- Model option: public id/label/description; private explicit Agent model binding including credentials. Browser cannot submit a raw binding, base_url, secret or module.
- Tool option: public id/label/description/risk summary and permitted environment IDs; private portable route + matching neutral catalogue descriptor. Roots/settings stay executor-local.
- Environment option: opaque public id/label, mapped to existing trusted route/placement choices. It is not an arbitrary filesystem path or a new sandbox promise.
- Preset: id/label/description, default model ID, tool IDs and optional environment choices, safe risk summary. All referenced options must exist; validate the complete catalogue at startup before enabling creation.

Design bounds: at most32 presets,32 model options,64 tool options,32 environment options; public identifiers <=128 UTF-8 bytes, titles <=128 bytes, descriptions <=2048 bytes. Use existing stricter provider/tool/route validators where applicable. Trusted definitions and resolved Agent options remain subject to all existing core limits.

Browser draft accepts only preset ID, selected model/tool/environment IDs, optional title, initial task and a trusted authority choice under advanced settings. Validate lengths/types/duplicates/unknown keys and resolve IDs server-side every time. A preset is a starting point, not an authorization policy; edits may use only deployment-exposed choices. Deployment constraints cannot be expanded by forged params. Tool route set and model catalogue must match exactly; deselected tools cannot be invoked. Required environment compatibility must be checked before starting an Agent. No live provider network health check or implicit tool execution during form validation.

Task-first form shows task/preset/capability summary. Expand model/tools/environment/name and then authority/constraints. Environment is conditional on selected capabilities. Mark edits and allow reset to preset defaults; never write back to presets. A trusted default authority must be explicit in host configuration (local node is valid when authority is enabled); advanced choices are allowlisted. Missing/unavailable default requires user action, not automatic authority selection/fallback. Any exposed placement adjustment chooses trusted predefined constraints, not arbitrary raw settings. No model-controlled autorouting or hidden fallback on unavailable options.

Creation is `Agent.start` then `Agent.input`, NOT a transaction. Generate a bounded opaque Agent id unless explicitly supported UI needs otherwise; title is separate safe metadata. On known create success / input failure retain the live handle and report that only input failed. On ambiguous remote create or input acknowledgement, report uncertainty and offer safe discovery/status inspection, never automatically resubmit or create a replacement. Disable duplicate clicks while command pending; this is not durable exactly-once semantics.

No system-prompt/behaviour-instruction editor in this phase: existing Agent options do not support it, and a text prefix is not an equivalent implementation. Presets select configured capabilities, not new workflows or Agent subclasses.

## 4. Shared ephemeral observation contracts (proposed APIs)

### 4.1 Agent

Add opt-in overloads, preserving existing snapshot and subscription defaults:

```elixir
Beamlet.Agent.snapshot(ref, view: :display)
Beamlet.Agent.subscribe(ref, sink, view: :display)
# Existing ack(ref, sequence) is still called by the subscribing sink itself.
```

Default `snapshot/1`, `subscribe/1,2`, envelope tuple, Ref, sequence and credit semantics stay compatible for CLI. Display subscriptions use the SAME snapshot envelope/credit path, not an event bus or independent journal. Ref and sequence correlation remain authoritative; stale messages from another Agent/turn cannot update current display. A later snapshot replaces the display projection; it is not appended as if it were a delta event.

Display includes a versioned bounded projection of already-retained Agent context and current activity:

- Safe optional instance metadata: title, preset id and effective public option IDs, validated <=4096 serialized bytes at creation under a new explicit optional `display_metadata` Agent option. No raw binding/config/credentials/module/root. Metadata is a description, not authorization; validation does not depend on Web. Existing callers need not supply it.
- Conversation entries from existing neutral context, with opaque stable entry IDs and turn association within this Agent incarnation. Record bounded entry/turn annotations alongside the source context when accepting/appending messages; the neutral messages themselves remain unchanged. Remove annotations with source context, never reconstruct turn boundaries from browser arrival order. Assistant/tool call identity retained; expose truncation rather than a fake valid model history. This is UI text, never fed back as model context.
- Current turn/terminal turn and actual model/tool/child activity identity/status from existing Server-owned state. Safe arguments and results are bounded; child refs are actual observed identities. Parent-child inspect is read-only by default. Do not invent model-driven delegation tools or executor placement information absent at the source.
- `coverage: :live_context`, `truncated`, omitted counts/reason as applicable. No complete event-history claim, timestamps inferred from receipt time, or replay cursor. Progress can be coalesced.

Projection budget: max32 displayed conversation entries,16 current activities,8KiB per text/argument/result field, aggregate display target128KiB, and never exceed existing snapshot envelope bounds. Preserve existing base final/progress behavior; fit/truncate/omit display into remaining safe budget rather than newly failing a previously valid default snapshot. Never mutate or evict model context to fit UI. No unbounded transcript retention; stable entry IDs are context metadata only, removed with their source state.

Normal binding and credentials are never projected. Render content as untrusted escaped text; tool/provider content can itself echo sensitive information and trusted tools are not a secret-erasure boundary. Do not dump raw process state, exceptions, HTTP envelopes or arbitrary maps for diagnostics. A prompt/response is not chain-of-thought evidence.

### 4.2 Runtime and Node

Proposed `Beamlet.Runtime.observation/0` returns a bounded owner-projected read of report information with receiver-local age/freshness, not private Directory state. Node exposes `Beamlet.Node.observation/0` (local safe configured roles/readiness) and `Beamlet.Node.observe(nodes)` (bounded explicit trusted-node aggregation). Reuse existing finite read/erpc patterns; no new globally registered query endpoint, blanket retry layer or authority identity coupling.

- At most32 trusted target nodes,8 concurrent reads,5s aggregate receive budget,1MiB complete response, explicit per-node failures and completeness.
- Per-node safe fields: name, configured roles when available, service readiness facts, capabilities, environment IDs, available pool quantities, source/age and unknown reasons. Total capacity is not presently available; do not invent x/total or physical utilization.
- Authority readiness is not inferred from executor report presence. Runtime reports are not a full role inventory. No report means unknown/not reported, not confirmed dead.
- Directory computes report age on its own VM and exports an age/duration; consumers never subtract monotonic timestamps from different machines.
- Reads must not execute a model/tool or change scheduling/admission. If actual executor location is not publicly available for an activity, display unknown rather than consult coordinator internals.

## 5. Workbench information architecture and state

Routes proposed:

- `/`: Agent list and task-first creation entry (not a metrics dashboard).
- `/agents/new`: expanded creation form.
- `/agents/:handle`: workbench for a verified server-side live identity.
- `/admin/nodes`, `/admin/presets`, `/admin/diagnostics`: read-only views.

Desktop shell: Agent list at left, conversation/turns in center, inspector opened on demand at right. Small screens use drawers; headings, keyboard focus, labels and state indicators remain usable without color alone. Long outputs are truncated/scrollable. Follow bottom while user is there; if reading older content, show a new-activity indicator rather than moving scroll. Do not claim token streaming (current adapter is non-streaming).

Discovery uses local explicit list plus trusted connected aggregate and renders complete/failures independently from items. Do not silently hydrate every discovered Agent with concurrent snapshots: query selected Agents and use bounded background refresh. A partial empty list is never 'no Agents'. Same IDs on different authorities remain distinct; opaque handle points to exact observed descriptor. Lookup descriptor fences PID replacement, live Ref fences incarnation. On handle expiry restart discovery or present stale state; do not rebind by name. Browser input never decodes arbitrary external terms, PIDs, atoms or modules.

Handles are memory-only, max4096 entries, expiring idle entries after1 hour; active selected handles refreshed, all invalidated on Web restart. A new handle can be obtained by fresh discovery, but old handle never becomes another instance. Keep secrets/transcripts out of URL, signed readable cookie session and browser storage. Safe instance display metadata lives with the Agent, so Web restart need not require a separate metadata database.

Business state (`idle/running/waiting/done/error/stopped`) is independent of command-pending and observation connection state. While active, allow editing a draft but do not enqueue or submit a second turn. Multi-tab/CLI conflicts render actual busy/unavailable/stale outcomes. No implicit retry after reconnect. Subscription ack occurs only from sink; offload bounded read/command calls with explicit ownership without leaving orphan tasks. Subscriber death only removes observation. Switching Agents explicitly unsubscribes; Web teardown does not close Agents.

Stop: show requested/unknown separately from observed turn status, never claim upstream cancellation or rollback. Close: explicit destructive confirmation in overflow menu; known close success ends the live view, no persistent archive. 'New with this configuration' uses the currently exposed trusted configuration IDs, not private snapshot binding. CLI-created/unknown-configuration Agents show unknown metadata and require a new preset selection instead of extracting credentials.

## 6. Management and security

Admin views reuse safe adapters, observation projections and inspection components; they are a different information hierarchy, not a separate role/tenant system. Nodes show reachability vs readiness vs report freshness; presets show actual startup source/defaults/references and unavailable reasons. Diagnostics link current Agent/turn/operation identities only where actually observed; no full trace database, raw log browser or exporter.

Management is read-only: no remote shell, arbitrary RPC, hot configuration, role switch, secret editor, module upload, restart/migration controls or automatic recovery. Available capacity is advisory, not reservation.

Preserve nonce CSP, CSRF, origin protections, output escaping, production secret failure and dev-only debugger/dashboard gates. No public unauthenticated deployment claim: retain loopback development default, document trusted network / authenticated reverse proxy protection for any shared deployment. This phase adds no login/SSO/RBAC. Browser navigation to admin is not authorization. An embedding enterprise must implement command/query/subscription/environment authorization if it needs private users/tenants; outer login alone is insufficient.

## 7. No persistence and future durable seam

No Ecto/Repo/migrations, database service, file transcript, localStorage/IndexedDB Agent cache, archive, event log, automatic replay or durable action implementation. Trusted operator config files are startup configuration, not saved user data. LiveView assigns and bounded handle maps are disposable UI state; existing Agent context stays Agent-owned.

On reconnect, read current display snapshot; show missing/truncated context when necessary. On Web restart handles disappear; rediscover surviving remote Agents. If Web embeds authority/executor, Web process-tree/VM restart may lose those Agents; do not imply remote-only survival. On authority loss show unavailable/unknown and never recreate. Future durable action may replace observation sources, but this task introduces no speculative storage interface or mock recovered history.

## 8. Compatibility, rollout and rollback

Opt-in Agent display keeps CLI default projections and query identity island unchanged. New Node/Runtime reads are additive. Host disabled preserves ordinary umbrella loading and existing backend release closures. Web-specific release packaging, physical deployment and paid-provider acceptance are not included.

Roll out in children with deterministic local/named peer fixtures. Feature-enable only after both shared contract and resolver gates pass. Rollback disables Web-owned host / restores previous Web app and matching config, not business undo or state recovery. Do not undo unrelated working tree changes. Final spec updates describe implemented behavior only, not these proposed APIs before they land.
