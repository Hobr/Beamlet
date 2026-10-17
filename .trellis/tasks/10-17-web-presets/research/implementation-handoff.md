# Web host/preset implementation handoff

Implementation is ready for independent review. This report does not accept the whole child or parent. All writes are scoped to Web-owned adapters/tests/docs and this requested output artifact. No Agent/Runtime/Node/CLI/daemon source or shared spec was edited. No task pointer, branch, staging, commit or archive operations occurred.

## Ownership and changed files

- `apps/beamlet_web/HOST.md`
- `apps/beamlet_web/lib/beamlet_web/agents.ex`
- `apps/beamlet_web/lib/beamlet_web/handles.ex`
- `apps/beamlet_web/lib/beamlet_web/host.ex`
- `apps/beamlet_web/lib/beamlet_web/host/bootstrap.ex`
- `apps/beamlet_web/lib/beamlet_web/presets.ex`
- `apps/beamlet_web/priv/examples/host.exs`
- `apps/beamlet_web/test/beamlet_web/bootstrap_distributed_test.exs`
- `apps/beamlet_web/test/beamlet_web/host_distributed_test.exs`
- `apps/beamlet_web/test/beamlet_web/host_test.exs`
- `apps/beamlet_web/test/beamlet_web/presets_test.exs`
- `apps/beamlet_web/test/support/host_peer.ex`
- `apps/beamlet_web/lib/beamlet_web/application.ex`
- `apps/beamlet_web/mix.exs`
- `apps/beamlet_web/test/test_helper.exs`

Application adds a disabled Host sibling before existing Telemetry/PubSub/Endpoint. Host owns one Node, then immutable Presets, disposable Handles and temporary Bootstrap, using rest_for_one. A navigation/catalogue crash cannot restart the earlier Node; Node loss clears later navigation. Host/Web restart clears handles, and embedded authority loss can lose Agents. Endpoint protections/routes remain unchanged. Web manifest directly declares Node/Agent/Actions/Harness, test-only Runtime, and OTP crypto. No daemon/CLI dependency or UI implementation.

## Exact public configuration and API

The complete implemented schema and API contract is in `apps/beamlet_web/HOST.md` (included below for review). Trusted deterministic example: `apps/beamlet_web/priv/examples/host.exs`. Example is not auto-imported. Config.Reader tests and actual local all-role / named interaction-only-to-remote turns confirmed it produces `Local example response` with no paid model/key.

# Trusted Web host and adapter API

The endpoint still starts with the host disabled. No new UI routes are supplied in
this stage. Startup-only `config :beamlet_web, :host, settings` enables the backend
adapters. Review and explicitly import `priv/examples/host.exs` from `config/dev.exs`
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

`Presets.describe/0` returns safe maps of labels/descriptions, preset public
reference defaults, tool public environment choices, and default authority.
`Presets.reset(preset_id)` returns `{:ok, draft}`. Draft string keys are exactly
`preset`, `model`, `tools`, `environment` (nil permitted when not required),
`authority`, `title`, `task` (UTF-8 <=65536 bytes). Unknown keys, wrong types,
duplicate IDs, excess counts and private values reject `{:error, :invalid_draft}`.
Selections may use only exposed deployment choices. Empty task is a valid core
input; UI task requirements are the next child's concern.

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
this is not durable exactly-once behavior. Calls are bounded by existing public
Agent control calls, not model completion. Caller abandonment cannot undo dispatch.
Future LiveView helpers must own/cancel their callers and retain uncertainty.

`Agents.discover(trusted_atom_targets)` preserves Node discovery complete/failures.
Resolve target names with Cluster from trusted config only; explicitly include
`node()` for local nondistributed discovery. `Agents.attach(exact_descriptor)` /
`Handles.remember(descriptor)` returns an opaque random32-byte Base64url handle
only after public exact-descriptor lookup. `Handles.fetch(handle)` rechecks the
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
database, file transcript, replay, recovery, system-prompt editor, online mutation,
workbench/admin implementation or Web release packaging is included.


## PA evidence matrix

| Requirement | Implementation and checks |
| --- | --- |
| PA1 | Default Host has empty children; no Node/Registry/Gateway/Presets/Handles or connection change; endpoint alive. Four interaction-containing subsets run actual trees. Named interaction-only host connects configured remote authority/executor once and creates/observes there. Bootstrap suspended-peer deadline and Host loss assert actual task/controller/helper DOWN before peer resumes. |
| PA2 | Immutable catalogue/reset, actual portable routes and exact matching descriptor keys, selected-tool environment compatibility, no-tool no environment requirement, deselection drops routes/catalogue, explicit private model binding, metadata selection IDs. Exact4096 serialized metadata accepted/4097 rejected. Source config/reset unchanged; created Agent metadata observed through public display snapshot. |
| PA3 | Unknown browser keys/raw bindings/nodes/modules, wrong types/improper lists, duplicate/missing IDs, UTF-8 and128-byte title edge,65536/65537 task bytes, count caps, invalid adapter fields and references reject static errors. Model credentials remain in resolver only; no private base URL/credentials/binding in descriptors/reset. Tool roots/settings remain Node executor-local. Shared ModelBinding/Operation/Catalogue/Display validators enforce existing core shapes/envelopes. |
| PA4 | Actual1024-byte Runtime executable ceiling rejects a2000-byte input after confirmed creation; Ref/handle retained. Empty text is valid core input, so test deliberately uses actual ceiling. Suspended Agent yields input_unknown on lost acknowledgement; no closure/recreate. Unreachable trusted remote create is conservatively create_unknown. Trace barriers prove exactly one Agent.start and one Agent.input in confirmed-created/rejected-input path, and one start/zero input in unknown-create path. No automatic retry anywhere. |
| PA5 | Exact descriptor public lookup plus Ref/incarnation equality fence handles; same ID replacement never rebinds.1h idle expiry and4096 cap tested with controlled state; no Agent closure. Actual Handles death and explicit navigation restart clear handles while embedded Agent survives. Named Web application restart clears handles while remote Agent survives, rediscovered descriptor reattaches to same Ref. No transcript/storage dependency. |

## Executed checks and evidence limits

Logs and original inventories live at `/tmp/beamlet-web-presets-inventory`. Final gates have `.exit` artifacts (0): compile-delivery, format-delivery, credo-delivery, dialyzer-delivery, sobelow-delivery, web-delivery2, named-web-delivery. Final Web ordinary:23 passed/3 distributed excluded. Final named Web:3 actual distributed passed/23 ordinary excluded. Seed631927 named runs use a private ephemeral cookie generated in memory; no cookie is persisted in commands/report/logs.

Broader earlier candidate ordinary gate:244 passed/32 excluded (Harness35,Actions28,Runtime43/6excluded,Agent26,Node68/20excluded,Daemon5/2excluded,CLI18/1excluded,Web21/3excluded). The later delta is Web rest_for_one and two Web regression cases; final affected Web/static/named gates cover it. No claim that a246-test full umbrella gate ran. The earlier combined named gate passed88 Node +22 Web, including20+3 actual distributed cases and87 ordinary cases. It preceded final Web-only refinements; final named Web gate is fresh. The first detached combined named run has complete passing output but no separate exit-status file; final named gate has exit0. Prior prerequisite230 ordinary/27 named counts are not this child's results.

Both backend releases rebuilt with backend selector and production env. `check-release.sh` passed copied manifests/closures (Web/opposite-host exclusion), named daemon default/authority/executor service/RPC/pid/stop, remote bootstrap and deterministic Gateway turn,12 invalid runtime/config cases, copied CLI closure and independent stdin sessions preserving same Ref after quit/EOF then explicit close. Copied release evidence at `/tmp/beamlet-release-logs.FNx3Xy`; manifest hash logged in release-closure.log. No source cookie value logged.

Initial failed logs remain: web-test.log has4 fixture-path failures because umbrella child cwd differs; web-test2.log has1 incorrect test assumption that empty input is invalid (core accepts it). Fixed fixture path with __DIR__, and used a real executable ceiling to exercise confirmed-created/input-rejected. Credo initial/final/final2 logs retain style findings, corrected in final passing gates. No infrastructure failure, assertion weakening, business retry or Runtime composition100ms recurrence occurred.

No assets/UI changed, so asset build/deploy and browser walkthrough are excluded. No paid provider, physical host, pre-commit benchmark/SBOM or full check-local paid/physical workflow is claimed. LSP tooling emitted an unavailable/timed-out advisory; do not interpret it as clean. Existing-PLT Dialyzer used --no-check, analyzed all umbrella beams, zero errors/skips, no PLT refresh. Sobelow complete with no findings.

## Preservation and next owner work

Original status, full binary staged/worktree diffs and originally modified tracked-file SHA256 hashes captured before edits. Final original index binary diff is identical and every captured tracked-file hash matches. Prior untracked task/core files were not written; status inventory records them. Existing outside staged files remain staged; no staged changes were added or removed. Web diff whitespace passes.

Independent check must review complete15-path Web candidate and these contracts, then parent owns shared-spec synchronization and child acceptance. Workbench next needs task-first forms with public descriptors/draft reset; conditional environment controls; memory-only duplicate-click pending lock; owned bounded asynchronous Agent calls with unknown outcomes retained; safe exact-descriptor discovery/attach; display replacement/omission semantics and sink-owned acknowledgements; explicit destructive actions without navigation closure. No browser may receive resolved options, binding, trusted node atoms/PIDs or credential-bearing state. Management remains later sibling work.

Historical composition100ms risk remains unresolved after parent disposition, not called fixed/flaky/baseline-proved. On recurrence preserve correlated terminal/admission/worker timing and escalate; do not enlarge timeouts or retry. Same-host peers do not establish physical deployment. Outer login still does not create per-user core authorization. Command acknowledgement uncertainty cannot establish external absence, cancellation, rollback or exactly-once delivery.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Implemented Web-owned adapters; exact checks, boundaries and residual risks recorded in authoritative handoff."
    }
  ],
  "changedFiles": [
    "apps/beamlet_web/HOST.md",
    "apps/beamlet_web/lib/beamlet_web/agents.ex",
    "apps/beamlet_web/lib/beamlet_web/handles.ex",
    "apps/beamlet_web/lib/beamlet_web/host.ex",
    "apps/beamlet_web/lib/beamlet_web/host/bootstrap.ex",
    "apps/beamlet_web/lib/beamlet_web/presets.ex",
    "apps/beamlet_web/priv/examples/host.exs",
    "apps/beamlet_web/test/beamlet_web/bootstrap_distributed_test.exs",
    "apps/beamlet_web/test/beamlet_web/host_distributed_test.exs",
    "apps/beamlet_web/test/beamlet_web/host_test.exs",
    "apps/beamlet_web/test/beamlet_web/presets_test.exs",
    "apps/beamlet_web/test/support/host_peer.ex",
    "apps/beamlet_web/lib/beamlet_web/application.ex",
    "apps/beamlet_web/mix.exs",
    "apps/beamlet_web/test/test_helper.exs"
  ],
  "testsAddedOrUpdated": [
    "apps/beamlet_web/test/beamlet_web/bootstrap_distributed_test.exs",
    "apps/beamlet_web/test/beamlet_web/host_distributed_test.exs",
    "apps/beamlet_web/test/beamlet_web/host_test.exs",
    "apps/beamlet_web/test/beamlet_web/presets_test.exs",
    "apps/beamlet_web/test/support/host_peer.ex",
    "apps/beamlet_web/test/test_helper.exs"
  ],
  "commandsRun": [
    {
      "command": "mix compile --warnings-as-errors",
      "result": "passed",
      "summary": "Final Host supervision candidate compiled; compile-delivery.log, exit0."
    },
    {
      "command": "mix format --check-formatted",
      "result": "passed",
      "summary": "Final full format gate; format-delivery.log, exit0."
    },
    {
      "command": "mix credo --strict",
      "result": "passed",
      "summary": "126 source files,1058 mods/funs, no issues; credo-delivery.log."
    },
    {
      "command": "mix dialyzer --no-check",
      "result": "passed",
      "summary": "Existing dev PLT, no refresh; zero errors/skips; dialyzer-delivery.log."
    },
    {
      "command": "mix sobelow",
      "result": "passed",
      "summary": "Scan complete; sobelow-delivery.log."
    },
    {
      "command": "mix test apps/beamlet_web/test",
      "result": "passed",
      "summary": "Final23 passed/3 distributed excluded; web-delivery2.log."
    },
    {
      "command": "named mix test apps/beamlet_web/test --only distributed --seed631927",
      "result": "passed",
      "summary": "Final3 actual named passed/23 ordinary excluded; named-web-delivery.log."
    },
    {
      "command": "named mix test apps/beamlet_node/test apps/beamlet_web/test --include distributed --seed631927",
      "result": "passed",
      "summary": "Earlier candidate: Node88,Web22 passed;20 Node+3 Web actual distributed,87 ordinary included; named.log."
    },
    {
      "command": "mix test --seed631927",
      "result": "passed",
      "summary": "Earlier candidate244 ordinary passed/32 distributed excluded; ordinary.log. Later changes are Web rest_for_one and two focused Web tests, validated with final Web gates."
    },
    {
      "command": "BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite; equivalent beamlet_cli build",
      "result": "passed",
      "summary": "Both releases rebuilt successfully; release-daemon.log/release-cli.log."
    },
    {
      "command": "bash scripts/deployment/check-release.sh",
      "result": "passed",
      "summary": "Copied daemon/CLI closures; daemon three named configurations, RPC/pid/stop, remote bootstrap/Gateway,12 invalid configs, CLI independent stdin/quit/EOF/sameRef/close gates passed."
    },
    {
      "command": "git diff --check and original index/tracked-file hash comparison",
      "result": "passed",
      "summary": "Index binary diff unchanged; all original modified tracked paths SHA256 unchanged; no stage/unstage/reset/revert."
    }
  ],
  "validationOutput": [
    "Final Web23 ordinary +3 actual distributed passed. Full ordinary snapshot244 passed/32 excluded; do not substitute historical prerequisite230/27 counts.",
    "Backend copied evidence: /tmp/beamlet-release-logs.FNx3Xy; complete gate logs: /tmp/beamlet-web-presets-inventory.",
    "Preserved initial failures: fixture cwd4 failures; empty input assumed invalid1 failure (core accepts empty text); strict Credo style findings. Corrected source/test assumptions without weakening core assertions."
  ],
  "residualRisks": [
    "Independent full-scope check and parent-owned shared-spec synchronization remain; child/parent acceptance not asserted.",
    "Historical Runtime composition100ms failure remains unexplained; no recurrence observed in this child gates, no fixed/flaky/baseline claim.",
    "Named peers are same-host only; physical hosts, paid providers and visual UI acceptance excluded.",
    "LSP advisory tooling was unavailable/timed out for at least one touched file; static checks above are explicit evidence, not LSP cleanliness."
  ],
  "noStagedFiles": false,
  "diffSummary": "15 Web-owned source/manifest/test/example/doc paths; no core/shared-spec/UI edits. Existing outside staged files preserved exactly.",
  "reviewFindings": [
    "Self-review: no remaining blocker identified; independent review pending. Host uses rest_for_one so navigation loss cannot restart earlier Node; tested actual Handles process death."
  ],
  "manualNotes": "No commit, staging, task-pointer, branch, archive or future sibling change. noStagedFiles=false describes existing outside staged files; this worker staged nothing. Trusted example is explicitly opt-in and tested via Config.Reader and actual local/remote deterministic turns."
}
```
