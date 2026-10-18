# Trusted Web host and adapter API

The endpoint still starts with the host disabled. LiveView workbench and read-only
management routes are described in [WORKBENCH.md](WORKBENCH.md) and the Web
management spec; this file covers startup configuration and adapters. Startup-only
`config :beamlet_web, :host, settings` enables the backend adapters. Review and
explicitly import `priv/examples/host.exs` from `config/dev.exs`
(using its path relative to that file) for a deterministic local response without
network provider calls, keys or tools. Nothing provisions a paid model automatically.

Only one Node tree may run per VM. Leave CLI and daemon hosts disabled in a Web VM.
Host settings are a unique-key keyword list: `enabled` (default false), `node`
(default `[roles: [:interaction]]`), `allowed_nodes`, `peers` (both default empty),
and `catalogue` (default empty). Node configuration is validated by Node itself;
roles must include interaction. All four interaction-containing subsets work.
Peers are distinct trusted names, max32, subset of Cluster's validated allowlist.
An owned temporary task connects sequentially once after Node startup, with each
Cluster attempt bounded to5s. Failure preserves local services. Host loss/deadline
retires helpers; OTP may finish an initiated handshake later. No browser operation
connects or retries. Config/env updates do not change a running host.

The catalogue is an atom-key map with `models`, `tools`, `environments`, `presets`,
`authorities` (maps keyed by public string IDs), and `default_authority` (public ID
or nil). Entry keys are strict; every entry has `title` and optional `description`.
IDs/titles are nonempty UTF-8 <=128 bytes; descriptions <=2048 bytes. Bounds are32
presets/models/environments/authorities and64 tools. Private fields by entry:

| Entry | Additional fields |
| --- | --- |
| model | `binding`: explicit immutable Agent model binding; adapter must be in the trusted Node model_providers registry (built-ins by default) |
| tool | `route`: portable Agent Tool route without environment; `descriptor`: matching neutral Harness descriptor; `environments`: distinct allowed public environment IDs (empty means no environment requirement) |
| environment | `value`: existing opaque core environment ID, never a root or settings |
| preset | `model`: default model ID; `tools`: distinct default tool IDs; optional `environment`: public ID |
| authority | `target`: `:local` or trusted allowed node-name string |

Tool descriptor names must be globally unique. Presets/reference/adapter shapes
and core route/catalogue limits are validated at startup without provider/tool IO
or key-env fallback. Executor roots/settings stay in trusted Node profiles.
Default selection is explicit: absent default authority leaves drafts unresolved
until an exposed authority is chosen. No availability fallback exists.

UI language is not a host setting and is not part of the trusted `:host` keyword
list: `config :beamlet_web, :default_locale` (shipped as `"zh_CN"`, the other
catalogue is `"en"`) only selects presentation, the per-request choice comes from
the session or `?locale=`, and no Agent/Node/Runtime behaviour depends on either.
See the language section of [WORKBENCH.md](WORKBENCH.md#language).

`Presets.describe/0` returns safe maps of labels/descriptions, preset public
reference defaults, tool public environment choices, and default authority.
`Presets.reset(preset_id)` returns `{:ok, draft}`. Draft string keys are exactly
`preset`, `model`, `tools`, `environment` (nil permitted when not required),
`authority`, `title`, `task` (UTF-8 <=65536 bytes). Unknown keys, wrong types,
duplicate IDs, excess counts and private values reject `{:error, :invalid_draft}`.
Selections may use only exposed deployment choices. Empty task is a valid core
input; the creation form itself requires task text.

`Presets.resolve(draft)` returns `{:ok, %{authority: target, task: text, options:
agent_options}}` server-side only. Options contain exact matching tools/catalogue,
immutable binding and shared-contract display_metadata (<=4096 serialized bytes).
Never place this resolved object in browser assigns, sessions, logs or URLs.
Reset only returns a new draft. It cannot edit presets or existing instances.
Pure `configuration/2,3`, `describe/1`, `reset/2`, `resolve/2` support startup/tests;
the running GenServer has no configuration mutation API.

`Agents.create(draft)` performs one start then one input. Outcomes:

- `{:rejected, :invalid_draft}`: no start dispatched.
- `{:create_unknown, %{authority: atom, id: generated_id}}`: no confirmed Ref;
  even static remote errors do not prove no creation. Inspect discovery explicitly.
- `{:created, %{ref: ref, navigation: {:ok, handle} | {:error, reason}, input:
  {:accepted, turn} | {:rejected, static_reason} | :input_unknown}}`: confirmed
  creation is retained independently of navigation or input success.

`Agents.input(ref, text)` uses the same input variants. Known busy/invalid/stale
rejections are distinct from unknown acknowledgement. There is zero automatic
resubmission/recreation. Next UI must lock duplicate clicks in memory while pending;
this is not durable exactly-once behavior. Input uses the existing five-second
Agent command budget; remote creation uses five-second erpc. Local creation calls
DynamicSupervisor admission without a finite timeout, so create has no whole-call
deadline. Caller abandonment cannot undo dispatch or prevent a queued local
creation from completing later. LiveView helpers own callers, impose
an explicit UI deadline, handle caller exits, and retain uncertainty for explicit
discovery rather than retry. Presets process loss may exit before start dispatch;
that is an adapter availability failure, not evidence of business rejection.

Navigation owner loss or timeout returns `{:error, :unavailable}` in the created
result and does not prevent the single input dispatch. The confirmed Ref remains
available even without a handle. Handle fetch reports the same static availability
error if its process is absent or stalled. A timed-out navigation insertion may
complete later; it stores only bounded identity data and never owns Agent life.

`Agents.discover(trusted_atom_targets)` preserves Node discovery complete/failures.
Resolve target names with Cluster from trusted config only; explicitly include
`node()` for local nondistributed discovery. `Agents.attach(exact_descriptor)` /
`Handles.remember(descriptor)` returns an opaque 32-character Base64url handle
(24 random bytes) only after public exact-descriptor lookup. `Handles.fetch(handle)` rechecks the
observed PID and Ref/incarnation; stale/replaced/expired handles fail and never
rebind by name. Max4096 entries,1h idle expiry with periodic bounded map cleanup;
full maps reject new entries. Handles store descriptor/Ref/touch time only, never
transcripts/credentials, and never close Agents. Host uses rest_for_one with Node first: navigation/catalogue process loss does not
restart Node; Node loss clears the later navigation processes. Host subtree/Web restart clears
navigation. Fresh discovery can attach surviving remote Agents; embedded authority
restart loses its Agents and cannot recover them. Handles are not authorization.

Keep development loopback binding. Shared deployments require trusted-network or
authenticated reverse-proxy controls. Outer login alone supplies no per-user core
command/query/subscription/environment authorization. No accounts/RBAC/tenancy or
public unauthenticated deployment is provided. Preserve endpoint CSP, CSRF, origin
protection, escaping and production SECRET_KEY_BASE failure. No browser storage,
database, file transcript, replay, recovery, system-prompt editor, online mutation
or Web release packaging is included; management routes remain read-only.
