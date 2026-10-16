# Backend CLI and Release

## 1. Scope / Trigger

Use when changing CLI clients, release packaging or deployment configuration.
Node owns this seam; Agent remains the only business loop. Source anchors:
`apps/beamlet_node/lib/beamlet/node/cli.ex`, root `mix.exs`,
`config/backend_runtime.exs`, `rel/env.sh.eex`, `scripts/deployment/`.
Local independent review passed. User removed physical multi-host acceptance from
this MVP's completion criteria; physical execution remains untested.

## 2. Signatures

```bash
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_node
bash scripts/deployment/check-release.sh
bash scripts/deployment/check-local.sh
```

```elixir
alias Beamlet.Node.CLI
{:ok, authority} = CLI.authority("authority@host.internal", trusted_names)
:ok = CLI.connect("authority@host.internal", trusted_names)
{:ok, ref} = CLI.create(authority, options)
{:ok, turn} = CLI.input(ref, "hello")
CLI.watch(ref, timeout: 30_000, events: 128)
CLI.snapshot(ref)
CLI.status(ref)
CLI.stop(ref)
CLI.close(ref)
```

Delegation and peers use the public Agent APIs with live refs; see
[Agent and Node](./agent-orchestration.md). No stable CLI ID lookup exists.

## 3. Contracts

The backend selector limits umbrella apps to the five core apps, disables the
Phoenix build listener and isolates build output under `_build/backend`.
Release root is `beamlet_node: :permanent`; artifact is
`_build/backend/prod/rel/beamlet_node`. Inspect `.rel`, required `.app` dependency
edges and shipped `lib/`: exclude Web/Phoenix/PubSub/Plug/Bandit/WebSock apps.
Req optional Plug metadata/helper modules do not mean the Plug app ships.
Ordinary umbrella builds may activate optional Plug through Web and are not the
verified backend deployment build.

Backend runtime config requires absolute `BEAMLET_CONFIG`, read with
`Config.Reader.read!`. This is trusted local Elixir code with operator privileges;
never accept its path/content from model output. `:beamlet_node, :boot` selects
validated roles/profiles/routes/pools. Authority needs no key or workspace root.
The ordinary `config/runtime.exs` production Web secret check is preserved.

Release environment requires `RELEASE_NODE`, `RELEASE_COOKIE`, `BEAMLET_CONFIG`;
selects long names and two schedulers. `BEAMLET_DIST_PORT` defaults to9100 for the
service. Control helpers rpc/remote/restart/stop/pid use ephemeral port0: reusing
the service port causes eaddrinuse before RPC. Static connection is explicit;
trusted hosts need reachable names, EPMD4369 and bidirectional distribution ports.
Securely provision cookies/keys locally; never include them in evidence.

CLI authority accepts a matching name from a trusted list of at most32 entries;
name at most255 bytes with the declared ASCII node@host syntax. Only deployment
names are atomized. Ref is live/ephemeral; retain it in one IEx/script session.
Input/snapshot/stop/close directly delegate to Agent.
Watch accepts only a keyword list with timeout/events keys, timeout1..60000ms
(default5000), events1..256 (default64). It subscribes, consumes and acknowledges
from the same sink, then unsubscribes in after. Terminal statuses done/error/stopped
return `{:ok, snapshot}`. It prints at most4096 codepoints per event using bounded
inspect. Its receive deadline excludes separate bounded Agent control calls and
synchronous terminal IO; do not promise a strict whole-call wall-clock deadline.
Timeout/event-limit never cancels business work. Rewatch gets a fresh snapshot
without replay promises; subscriber loss does not own the Agent lifetime.

Deployment runbook contains combined/isolated role examples and teardown.
`http-fixture.py` is a bounded local socket fixture, not an upstream provider:
at most16 requests,30s accept waits,10s whole-request deadlines including headers,
malformed-length rejection, joined deadline timers. Its final observation digest
must match expected Tool JSON to establish a successful marker read. Workspace
trust and provider uncertainty remain as specified in [Native Harness](./harness-providers.md).

## 4. Validation & Error Matrix

| Condition | Observation |
| --- | --- |
| Invalid/missing allowlisted authority | invalid_authority |
| Failed explicit connect | unavailable |
| Malformed/unknown/over-limit watch options | invalid_watch_options before subscribe |
| Event budget exhausted | event_limit; subscription removed |
| Receive deadline/loss | timeout_or_loss, or underlying unavailable during control |
| Dead ref/start failure | public Agent error; no fallback/retry |
| Missing/relative BEAMLET_CONFIG | startup failure; relative path has explicit error |
| Missing Web production secret | ordinary production Web boot still fails |
| Physical-host execution | untested; removed from MVP completion criteria by user |

## 5. Good/Base/Bad Cases

Good: build with selector, verify copied named startup/RPC/stop, connect explicit
trusted authorities and ack from the watcher process.
Base: authority-only copied release boots without model/web secrets or executor.
Bad: use eval-only checks to claim distributed service boot, serialize live refs
as durable IDs, or use local peers as distinct physical-host evidence.

## 6. Tests Required

Preserve CLI malformed-option, subscription cleanup/event-limit, dead-ref and
authority-loss tests. Preserve three-role real HTTP→workspace→model correlation,
wrong environment/no fallback, stop during held request, executor loss/no replay.
Run named distributed tests explicitly, not only ordinary ExUnit exclusions.
`check-release.sh` checks required dependency closure and copied eval role boot;
`check-named-release.py` additionally exercises foreground long-name start, RPC
role assertions, fixed service port and stop with bounded process cleanup.
Keep default production missing-secret and Web CSP checks. Fixture tests include
complete tool_calls/stop POSTs, malformed length and slow/incomplete headers.
Report LSP coverage and existing-PLT analysis separately from PLT refresh.
Optional future physical evidence should record B/C on distinct machines,
identities/build hash, C-only marker, explicit authority, stop/loss/no fallback and
teardown. It is not a required gate for this delivery. Live paid
provider smoke is optional and requires separate operator authorization.

## 7. Wrong vs Correct

Wrong: give RPC helpers the fixed service listener, or infer release health from
an unnamed eval process that never exercises distribution.
Correct: use ephemeral control ports, preserve the service fixed port, and test
copied named start/RPC/stop outside the checkout. Keep local, physical and live
provider evidence separate.
