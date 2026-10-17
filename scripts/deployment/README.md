# Daemon deployment and acceptance

## One artifact, three startup configurations

Build from the checkout with the project OTP/Elixir toolchain:

```sh
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite
bash scripts/deployment/check-release.sh
```

The backend selector compiles the five libraries plus daemon, excludes Web/CLI,
uses isolated `_build/backend`, and avoids Req's optional Plug dependency from
Web. The release has its own `config/daemon_runtime.exs`; ordinary Web production
still fails without SECRET_KEY_BASE. No dummy Web secret is needed for daemon.

Copy `_build/backend/prod/rel/beamlet_daemon` outside the checkout, to compatible
OS/architecture/OTP hosts. **Do not build role-specific artifacts.** Copy and edit
[daemon.example.exs](daemon.example.exs) to an absolute operator-owned file:

```elixir
import Config
config :beamlet_daemon,
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

BEAMLET_CONFIG is trusted Elixir **code with deployment-user privileges**, not a
sandbox or model input. Restrict file ownership/permissions and never load
model-provided paths/modules. The runtime reader accepts only :beamlet_daemon
settings (enabled/node/allowed_nodes/peers), normalizes and validates them, then
explicitly enables the host. Reader/validation errors are static and do not
render raw values, paths or exception causes. Arbitrary code in a trusted file
can itself print or leak data; sanitizing reader failures cannot prevent that.
Ordinary umbrella startup has enabled=false and an empty daemon tree, with no
cluster or stdin side effects. Changes to Application env after startup do not
reconfigure the running host.

Authority boot needs no user key or workspace. Register trusted model adapters
with `model_providers` on authority/executor (defaults: openai-compatible and
deterministic). Executor Tool profiles contain only executor-local settings and
roots; use bounded pools and the bundled Tool allowlist. Agent creation supplies
one immutable model/provider/config/credentials/placement binding. Never statically
provision user model keys in executor profiles; no key_env fallback exists.

## Service and cluster bootstrap

Provision these variables through a restricted service environment, without shell
tracing or printing the cookie:

- RELEASE_NODE: long name, e.g. `authority@b.example.internal`.
- RELEASE_COOKIE: securely shared by trusted cluster members.
- BEAMLET_CONFIG: absolute trusted config path.
- BEAMLET_DIST_PORT: fixed service distribution port, default **9100**.

Run `bin/beamlet_daemon start` under a service manager (or `start_iex` for a trusted
operator session). `rel/env.sh.eex` uses long names and two schedulers. The rpc,
remote, restart, stop and pid helper VMs use ephemeral port **0**, never the service
port. Stop with `bin/beamlet_daemon stop`; inspect the service manager and sockets
before treating shutdown as complete. EPMD TCP4369 and selected distribution ports
must be reachable bidirectionally. Use resolvable long names on a trusted private
network/firewall: cookie distribution permits trusted code execution, not Internet
or multi-tenant authentication. TLS distribution rollout is not implemented.

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
Discovery/reattachment and a standalone CLI session/release are subsequent tasks,
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

check-release.sh copies one artifact outside source/deps, fingerprints its file
manifest, checks .rel/.app/lib dependency closure (no CLI/Web/Phoenix/Plug/Bandit/
WebSock), and exercises default/authority-only/executor-only **named start, RPC,
pid and stop** on default service port9100. It then runs authority and executor
copies/configurations from that same artifact on19101/19102, bootstrap-connects,
and completes one deterministic remote Gateway turn. It checks failed-peer local
continuation and11 malformed runtime/config rejections without sentinel leakage.
Set BEAMLET_CHECK_LOG_DIR to retain logs in a chosen absolute directory; otherwise
a printed temporary evidence directory is retained. **Python 3.11+** is required
for the named-release checker (`sys.exception()` and exception `add_note()`);
its cleanup regression suite was verified on Python 3.14. EPMD/local sockets and
free ports9100/19101/19102 are required. The seven library combinations are tested
separately and are not daemon role choices.

`bash scripts/deployment/check-local.sh` runs the available daemon-stage gates and
explicitly reports final two-host/CLI acceptance as deferred. It does not attest
parent completion. Ordinary and named distributed actual counts, failure logs,
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
beamlet_daemon --overwrite` and the equivalent `mix release beamlet_cli --overwrite`.
The backend compilation selector includes both hosts; each release dependency
closure contains only its own host and excludes Web. Ordinary umbrella loading
starts neither host's Node and never reads stdin.

Copy the CLI release directory and `cli.example.exs` outside the checkout. Set
absolute `BEAMLET_CONFIG`, unique long `RELEASE_NODE`, trusted `RELEASE_COOKIE`
and an available `BEAMLET_DIST_PORT` (0 selects ephemeral). Run
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

`check-release.sh` now checks both rebuilt artifacts, including the same daemon
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
