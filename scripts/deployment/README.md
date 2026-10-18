# Server deployment and acceptance

The independent hosts are `beamlet_app_server` (`Beamlet.Server`) and
`beamlet_app_web` (`Beamlet.Web`); the other OTP apps remain embeddable capabilities.

## Breaking migration

| Old | New |
| --- | --- |
| `apps/beamlet_daemon`, `:beamlet_daemon` | `apps/beamlet_app_server`, `:beamlet_app_server` |
| `Beamlet.Daemon` and submodules | `Beamlet.Server` and submodules |
| `apps/beamlet_web`, `:beamlet_web` | `apps/beamlet_app_web`, `:beamlet_app_web` |
| `bin/beamlet_daemon` | `bin/beamlet_server` |
| `daemon.example.exs` | `server.example.exs` |

Update config namespaces and service commands and deploy a rebuilt complete artifact
with matching config. There are no old aliases, forwarding modules or config fallbacks.
The Web release stays `beamlet_web`; its module namespace, session cookie and salts
stay unchanged. CLI naming stays unchanged. Unnamed `mix release` now selects
`beamlet_server`; `mix release beamlet_daemon` is no longer supported.


## One artifact, three startup configurations

Build from the checkout with the project OTP/Elixir toolchain:

```sh
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_server --overwrite
bash scripts/deployment/check-release.sh
```

The backend selector compiles seven libraries (five core plus storage and i18n)
and both hosts, excluding Web, under isolated `_build/backend`. Each release
includes only its own dependency closure: the daemon excludes CLI/i18n/Gettext,
and the CLI excludes daemon/Web. This also avoids Req's optional Plug dependency
from Web. All three named releases use Mix's default bundled
`config/runtime.exs`; daemon and CLI do not require a Web secret.

Shared `config/config.exs` imports dev/test/prod build configuration. Mix embeds
those values in `sys.config` and copies `config/runtime.exs` to
`releases/0.1.0/runtime.exs`. Runtime configuration is evaluated before application
startup. Only the selected native `RELEASE_NAME` activates its host; ordinary
source/library loading stays opt-in. Keep one enabled host/Node per VM.

Copy the release directory outside the checkout to a compatible OS/architecture.
The target needs neither project source nor Mix; bundled ERTS still needs matching
system/native libraries. When rebuilding a previously customized release, use a
fresh output directory: `--overwrite` may retain obsolete files from an older
artifact (including retired wrappers/apps). Remove only the generated host release
directory before rebuilding; deploy a complete fresh tree, not an overlay.
Build assets before assembling Web:

```sh
MIX_ENV=prod mix compile --warnings-as-errors
MIX_ENV=prod mix tailwind beamlet_web --minify
MIX_ENV=prod mix esbuild beamlet_web --minify
MIX_ENV=prod mix phx.digest
MIX_ENV=prod mix release beamlet_web --overwrite
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_cli --overwrite
```

For Web, provide the existing `SECRET_KEY_BASE` securely and run
`bin/beamlet_web start`; the release enables Endpoint serving and the Web host.
Production source-run Web retains its required-secret check. Backend releases
neither ship Web nor need a dummy secret.

**Do not build role-specific artifacts.** Application settings examples in
[server.example.exs](server.example.exs) and [cli.example.exs](cli.example.exs)
are snippets to adapt in shared build config or the bundled `runtime.exs`, not
automatically loaded external files. For example:

```elixir
config :beamlet_app_server,
  node: [], # default [:authority, :executor]
  allowed_nodes: ["executor@c.example.internal"],
  peers: ["executor@c.example.internal"]
```

For authority-only use `node: [roles: [:authority]]`; for executor-only use
`node: [roles: [:executor]]`. Empty, duplicate, interaction and unknown roles
reject before any roles start. Only these startup choices are supported; there
is no runtime role switch/reconfiguration API. Code for both capabilities remains
in every copy. Node remains an embedded library with all seven combinations,
not an executable or an application boot-config reader.

There is no Beamlet external-config requirement, discovery, CLI config flag,
provider framework or deployment wrapper. The old external-file startup contract
is retired. Config/runtime scripts are trusted executable Elixir with deployment
user privileges, not a sandbox; restrict ownership and never use model input.
Existing host validators still reject invalid application settings at startup;
native script syntax/exception diagnostics are not sanitized by a custom reader.
Ordinary umbrella startup has enabled=false and an empty daemon tree. Changes to
Application env after startup do not reconfigure the running host. Runtime edits
require restart and must survive your next deployment; compile-time settings
(including `force_ssl`) require a rebuild. No hot reload or target-side editing
interface is provided.

Authority boot needs no user key or workspace. Register trusted model adapters
with `model_providers` on authority/executor (defaults: openai-compatible and
deterministic). Executor Tool profiles contain only executor-local settings and
roots; use bounded pools and the bundled Tool allowlist. Agent creation supplies
one immutable model/provider/config/credentials/placement binding. Never statically
provision user model keys in executor profiles; no key_env fallback exists.

## Service and cluster bootstrap

Use native Mix Release defaults, or its supported `RELEASE_NODE`,
`RELEASE_COOKIE`, `RELEASE_DISTRIBUTION`, `RELEASE_VM_ARGS` and
`RELEASE_REMOTE_VM_ARGS` settings. No custom shell requires identity/cookie/config
variables or pins a distribution port. Consult `mix help release` on the build
host for native settings and writable runtime configuration requirements.

Run `bin/beamlet_server start` in the foreground under systemd or containers
(or `start_iex` for a trusted session). On Unix, `bin/beamlet_server daemon`
provides native background operation; use native `pid`, `rpc`, and `stop` to
inspect and stop it. The copied-artifact check verifies background launch and
actual VM exit. Native `pid`, `rpc`, `remote`, `restart`, and `stop` controls
remain available with the service's identity/cookie. Native defaults include a
release cookie generated at build and a release-named node; use unique names for
simultaneous copies and rotate/provision cookies securely for trusted clustering.
Do not log cookies or enable shell tracing. `help` and `version` need no
application configuration or Web secret.

Stop with `bin/beamlet_server stop`; inspect the service manager and sockets
before treating shutdown as complete. EPMD TCP4369 and configured/native
distribution listeners must be reachable bidirectionally; choose any required
port restriction with native VM arguments, not a Beamlet fixed-port variable.
Use trusted private networks/firewalls: cookie distribution permits trusted code
execution, not Internet or multi-tenant authentication. TLS rollout is not supplied.

allowed_nodes is a trusted list of at most32 ASCII node@host names, each at
most255 bytes. peers is a distinct subset, at most32 entries. After Node is ready,
a host-owned temporary task connects each peer **once**, sequentially, using
Beamlet.Node.Cluster (up to5s per attempt). Startup supervision does not wait for
network completion; all32 failed peers can take approximately160s to exhaust.
Logs report only peer index and connected/unavailable. Failure leaves local service
alive. There is no background reconnect, scan, automatic discovery or business
retry/replay. Host loss cleans task/controller/helper ownership; OTP may still
finish an already initiated handshake later, so this is not network rollback.

Trusted operators may explicitly connect again without replaying business work:

```elixir
alias Beamlet.Node.Cluster
allowed = ["executor@c.example.internal"]
:ok = Cluster.connect("executor@c.example.internal", allowed)
{:ok, executor} = Cluster.authority("executor@c.example.internal", allowed)
{:ok, nodes} = Cluster.connected(allowed) # no implicit connection
```

## Deterministic and HTTP/Tool controls

From authority's IEx or one trusted RPC script (daemon ships Agent APIs, **not**
the terminal client), wait for an eligible Directory capacity report before input:

```elixir
{:ok, ref} = Beamlet.Agent.start(node(), id: "operator-demo",
  model: %{provider: "deterministic",
    config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}},
    placement: %{allowed_nodes: [executor]}})
:ok = Beamlet.Agent.subscribe(ref)
# Receive {:beamlet_agent, ^ref, sequence, {:snapshot, snapshot}} and acknowledge
# every sequence from this same sink with Beamlet.Agent.ack(ref, sequence).
{:ok, turn} = Beamlet.Agent.input(ref, "hello")
Beamlet.Agent.snapshot(ref)
Beamlet.Agent.stop_turn(ref)
:ok = Beamlet.Agent.unsubscribe(ref)
Beamlet.Agent.close(ref)
```

The initial subscribed snapshot precedes updates. Sink loss/timeout does not own
Agent lifetime; close is explicit. Do not serialize a live Ref as a durable handle.
Discovery/reattachment and a standalone CLI session belong to the CLI release,
not hidden Node executable dependencies. Keep live refs in the same operator
session/script. A CLI library test fixture exists but is not shipped in daemon.

For a no-spending HTTP→workspace→model exercise, run the unchanged
`python3 scripts/deployment/http-fixture.py --requests 16` on the executor: it
listens on loopback TCP18080, bounds requests to16, accept waits to30s and whole
requests to10s. Provision a dedicated permitted marker tree and a WorkspaceRead
Tool profile with root/max_bytes, capability, environment and bounded native pool.
Build the portable catalogue with WorkspaceRead.descriptor and route workspace_read
to that profile/environment with placement restricted to the executor. Agent model
binding uses provider openai-compatible, config
`%{"base_url" => "http://127.0.0.1:18080/v1", "model" => "fixture", "allow_local_http" => true}`
and explicit synthetic credentials `%{"api_key" => "synthetic-fixture-key"}`.
Loopback resolves on the selected executor. The fixture first requests marker.txt,
then reports the **complete Tool-observation digest**: compare it to SHA256 of the
expected Tool JSON content. A fixture final string alone is not marker-read proof.
The migrated named CLI integration preserves actual HTTP authorization/body
separation, digest correlation, wrong environment without fallback, a subsequent
turn after fresh capacity, stop during a held request, and executor loss/no replay.
No paid provider is contacted by these tests/fixture.

For authorized live calls use explicit Agent credentials and supported HTTPS text
nonstreaming Chat Completions/function tools. System CA trust/peer verification
remain mandatory; no custom CA/generation override or automatic retry is supplied.
Obtain separate endpoint/spending approval first. Never log requests, settings,
keys, roots or raw provider exceptions. Credentials are plaintext in authority and
executor processes/transient messages until ordinary cleanup; no secure erasure or
protection against administrator inspection/malicious provider echo is promised.
Children require their own explicit binding; peers do not inherit credentials.

Workspace checks reject traversal/symlinks/nonregular files and bound UTF-8 reads,
but are not atomic OS confinement. Provision controlled ancestors/backing writers,
preferably OS read-only. Hardlinks/mounts/TOCTOU/hostile writers remain outside the
trust boundary. Waiting delegation parents hold no executor capacity. Stop freezes
advancement and requests best-effort cleanup; DOWN/partition does not prove upstream
rollback, termination or billing cessation. Never replay uncertain business work.

## Checks, evidence and rollback

`check-release.sh` copies the daemon, CLI and Web artifacts outside source/deps,
fingerprints the copied trees, and checks isolated dependency closures. It tests
the same daemon artifact in default/authority-only/executor-only named modes,
native RPC/pid/stop without custom shell policy, failed-peer continuation,
authority-to-executor bootstrap and a deterministic remote Gateway turn. Fixtures
edit each copy's **bundled runtime.exs**; there is no external reader. Nine invalid
host options still fail without sentinel leakage, and a missing dataset is never
created at boot. Old reader-path/syntax-sanitization tests no longer apply to
native trusted scripts. Existing Python cleanup failure regressions remain intact.

CLI checks preserve foreground stdin, quit/EOF reattachment to the identical
Ref, explicit close, Unicode/identity pagination and actual PTY model output.
Web checks reject a missing secret, start with native identity/cookie defaults,
request real HTTP and CSS/JS from the copied digest artifact, and exercise native
controls. Web fixtures only change the copy's listener port/IP. No checked-in
probe file or new deployment variable is needed.

Set the existing `BEAMLET_CHECK_LOG_DIR` to retain logs in a chosen directory;
otherwise a printed temporary evidence directory is retained. Python3.11+,
EPMD/local sockets and native system libraries are required. The seven library
role combinations remain separate tests, not daemon startup choices.

`bash scripts/deployment/check-local.sh` runs format/compile/umbrella/named tests,
static analysis, all three release builds and the copied-artifact checks.
Successful local checks do not attest physical deployment or parent acceptance. Ordinary and named distributed actual counts, failure logs,
active-LSP limitations and copied hashes belong in task evidence. Use scheduler-only
ERL_FLAGS='+S 2:2' with an explicit securely generated parent --cookie for named Mix
tests; never put -setcookie in inherited ERL_FLAGS (observed parent/peer mismatch).

Physical multi-host execution and paid calls are **untested** and not authorized by
these checks. No SSH/deployment is performed. Matching builds/protocols are required;
rollback uses the retained old artifact **with its matching old config**, never a
mixed-version cluster. Restart is not recovery of lost Agents/history. Teardown
closes Agents explicitly, stops services/fixtures, verifies listeners, removes
temporary permitted fixtures and revokes any temporary credentials.

## Foreground interaction CLI

Build both backends with `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release
beamlet_server --overwrite` and the equivalent `mix release beamlet_cli --overwrite`.
The backend compilation selector includes both hosts; each release dependency
closure contains only its own host and excludes Web. Ordinary umbrella loading
starts neither host's Node and never reads stdin.

Copy the CLI release directory outside the checkout. Adapt `cli.example.exs`
application settings in shared config or its bundled runtime.exs; use native
Release settings for trusted distribution and a unique node identity. Run
`bin/beamlet_cli start` in the foreground; stdin accepts commands without IEx.
`help` describes the grammar. Use `connect authority@host`, then `agents`,
`attach authority@host agent-id local-alias`, `status local-alias`,
`input local-alias text`, `watch local-alias 5000 64`, `stop local-alias`, and
`close local-alias`. `create authority@host /absolute/agent-options.exs` reads
`:beamlet_cli, :agent_options`; see `agent-options.example.exs` for a deterministic
fixture. Real model bindings and Tool catalogue/routes use the same Agent options
as the HTTP/workspace integration, with operator-selected provider configuration
and dedicated credentials. Keep credential-bearing files accessible only to the
operator. Config files are **trusted executable Elixir code**, never a sandbox or
model-supplied input. The CLI has no generic eval command and sanitizes reader
errors without showing options, exceptions or paths.

Aliases are local real Refs, max128, never silently replaced. Use explicit
authority plus ID to disambiguate duplicate IDs; detach an old alias before
explicit reattachment. Attach reads a snapshot and submits no input. Quit, EOF,
detach, disconnect and watch timeout do not close an Agent. Only successful close
clears aliases. A new CLI can discover and attach the same surviving instance;
a stale Ref remains stale after ID reuse. Discovery is an observed partial view:
`complete` concerns requested nodes only. The terminal bounds rendering, commands
at65536 UTF-8 bytes, watch at256 events/60s/4096 codepoints per event, and rejects
overlong executable input as a whole. Overlong stdin ends the session. Stop is
not an upstream cancellation/rollback promise; no automatic business replay occurs.

`check-cli-release.py` pins `BEAMLET_LANG=en` for every copied CLI process, so its
English copy assertions (`error: invalid_command`, no `error:` in a healthy
session) stay deterministic now that Chinese is the shipped default; the language
switch itself is covered by `apps/beamlet_cli/test/beamlet/i18n_test.exs`.

`check-release.sh` checks all three rebuilt artifacts, including the same daemon
copy in three modes and three independent foreground CLI stdin sessions. The
first quits after create; the second discovers/attaches, operates and leaves via
EOF; RPC proves identical authority/PID/incarnation before the third explicitly
closes. `check-local.sh` runs the integrated gates and records each log separately.
Python3.11+ and the existing six teardown diagnostic regressions remain required.
These are same-host named peers and deterministic fixtures, not physical-host or
paid-provider acceptance.

Presentation reuses installed Owl0.13.1: help/nodes/agents/identity/status tables,
Owl.IO output and Owl.Data display bounds. Tables preserve authority/ID columns
regardless of terminal width; discovery shows at most8 full identities and explicit
total/shown/completeness/failure counts. Commands and identity handling remain
application code. The narrow raw-byte reader remains because Owl.IO.input reads an
unbounded line, trims executable text and retries required input/EOF. No full-screen
terminal engine or dependency/version change is needed.

### Terminal language

Terminal copy is translated with Gettext and ships in Simplified Chinese
(`zh_CN`, the default) and English (`en`). The CLI resolves its language once, in
`Beamlet.CLI.Runner.run/2` before any stdin is read, so a session cannot mix
languages mid-run. Precedence:

1. `config :beamlet_cli, :locale` — trusted build-time application config; it wins
   over everything (the host validator accepts `enabled`/`allowed_nodes` only);
2. `BEAMLET_LANG` — operator environment override, accepted spellings `zh`,
   `zh-cn`, `zh_CN`, `cn`, `en`, `en-us`, `en_US`;
3. `config :beamlet_cli, :default_locale` — shipped as `"zh_CN"`;
4. the shared default `zh_CN`.

`BEAMLET_LANG` deliberately outranks `:default_locale`, otherwise the shipped
default would make the documented override unreachable. An unusable value at any
step is skipped, so a typo falls back instead of disabling translation. The
choice only changes presentation: command grammar, table columns/order, bounds
and exit codes are identical in both languages, and a missing translation falls
back to the English msgid. Shared status/reason words come from the
`beamlet_i18n` catalogue; CLI-only text (help body, table headers, terminal
notices) comes from `apps/beamlet_cli/priv/gettext`.

### CLI review repair: Unicode input and complete identity traversal

Runner reads one raw byte with IO.binread/2 against65536 before retention.
For a terminal only, the exclusive stdin reader temporarily sets device encoding
Latin-1 to preserve original UTF-8 bytes (Unicode decoding otherwise replaces
malformed bytes); an after block restores the original encoding before output or
callbacks, including failure/EOF. Concurrent readers on that owned terminal are
unsupported. Pipes and injected nonterminal devices never change options.
LF is the delimiter; all preceding text and partial EOF are preserved. Native
read errors, invalid UTF-8 and overlong lines terminate with status1; EOF/quit
exit0. Executable input is never replaced or executed as a truncated prefix.

`agents [authority]` replaces one retained bounded discovery result (the existing
1MiB query bound); `agents-page N` traverses it without another query. Pages have
at most8 rows sorted by authority string, ID bytes and PID string. Query complete
refers only to requested targets; page/count describe display completeness.
Discovery remains an eventual, non-atomic cluster observation. Agents may change
or die after capture; refresh explicitly with agents, then restart traversal.
There is no implicit requery/retry and attaching still resolves the current ID.

Identity cells use `id64:` plus unpadded Base.url_encode64 UTF-8, accepted by attach
without evaluation. Copy the whole token and supply a safe explicit alias:
`attach host@local id64:dHdvIHdvcmRz a` attaches ID `two words`.
Simple nonreserved ASCII IDs remain accepted literally. To address a literal ID
starting with id64:, encode the entire ID. Decoded IDs retain the shared valid
UTF-8 1..128-byte contract, including whitespace and terminal controls. Tokens
are at most177 bytes; commands including encoded arguments still obey65536 bytes.
No shell grammar/eval or shared Agent ID restriction was introduced.

Installed Owl uses Ucwidth for CJK/emoji/combining terminal column measurement,
wrapping and truncation; actual beam behavior and copied closure are checked.
The independent4096-codepoint watch limit remains distinct from display width.

## Durable storage (stage F)

Durable storage is opt-in application configuration in the daemon's shared
config/bundled runtime.exs; omit the `storage:` block and the host stays ephemeral and
starts no database. Keys, the explicit migration command, the backup/restore
runbook and the full evidence are in
[the stage F release evidence](../../.trellis/tasks/archive/2026-10/10-18-durable-release-operations/research/release-evidence.md).

```elixir
config :beamlet_app_server,
  enabled: true,
  node: [roles: [:authority, :executor]],
  storage: [
    adapter: :sqlite,
    database: "/var/lib/beamlet/authority.db",
    dataset_id: "<authority uuid>",
    journal: [database: "/var/lib/beamlet/journal.db", dataset_id: "<journal uuid>"],
    executor_id: "<stable executor uuid>"
  ]
```

Install the datasets once, as an operator action — never at boot:

```sh
mix beamlet.storage.migrate --storage /etc/beamlet/storage.exs --roles authority,executor
```

`Beamlet.Storage.Host.status/1` reports `admission` (a live probe of the dataset,
distinct from Node/Repo readiness) and each dataset's open state. A restored
backup must be marked before use and stays refused, with admission off, until an
operator resolves it. The CLI host is interaction-only and needs no database.
