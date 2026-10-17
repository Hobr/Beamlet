# Backend deployment and acceptance

Build one compatible release for all participating hosts (same OS/architecture/OTP
ABI). From the checkout, run `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release
beamlet_node`. The selector excludes Web from the umbrella build and uses a separate
`_build/backend` tree. Without the selector, the umbrella compiles Phoenix and
Req can acquire optional Plug from Web; that is not the deployment build. Runtime
configuration is `config/backend_runtime.exs`; default Web production configuration
continues to require SECRET_KEY_BASE. No dummy secret is needed.

Run `bash scripts/deployment/check-release.sh` to inspect the shipped .rel/.app/lib
closure and boot all seven copied role combinations outside source/deps, including
named foreground startup, RPC and stop. Control helper VMs use ephemeral distribution
ports so they do not collide with the service listener. The local checker needs
Python3 and reserves ports19100/19101 while running. Run
`bash scripts/deployment/check-local.sh` for the automated acceptance gates.
These scripts are invoked through bash and need not be executable.

Copy `_build/backend/prod/rel/beamlet_node` to each host. Copy and edit
[node.example.exs](node.example.exs) to an absolute, operator-owned configuration
file outside the release. BEAMLET_CONFIG names this trusted Elixir file: it is code
with the deployment user's privileges. Never load model-provided configuration or
modules. Roles must be a unique nonempty subset of interaction/authority/executor.
Use authority-only B, executor-only C, interaction-only A initially. Local combined
roles use the same Gateway. Authority Node boot needs no user credentials or workspace root. Authority stores
each Agent's supplied binding privately after creation. Register trusted local
model adapters with `model_providers` on authority and executor; defaults register
`openai-compatible` and `deterministic`. Executor Tool profiles retain the bundled
Tool allowlist, portable IDs, bounded pools and trusted workspace roots. No model strings are converted to atoms.
The Node application consumes `Application.get_env(:beamlet_node, :boot)`.

Set RELEASE_NODE to a long name such as `authority@b.example.internal`,
RELEASE_COOKIE securely to the same cookie on all three nodes, BEAMLET_CONFIG to
the absolute local file and BEAMLET_DIST_PORT to a fixed local port (default 9100).
Never paste the cookie/key into transcripts or shell tracing. Provision the cookie through a restricted service environment file. Model keys
are supplied at Agent creation, never provisioned to executor profiles. Use the
system CA trust for HTTPS; this adapter
exposes no custom CA option and never disables verification. Supply model-specific
endpoint/model values compatible with text non-streaming Chat Completions and
standard function tools. No live provider call is needed for boot/readiness.

Run `bin/beamlet_node start` under a service manager (or `start_iex` for a supervised
interactive trial). The rel env template selects long names, two schedulers and a
fixed distribution port. All hosts must resolve each other's names and reach EPMD
TCP 4369 and the chosen TCP distribution ports in both directions. Use only a
trusted private network with firewall restrictions: cookie distribution is trusted
code execution, not an Internet authentication system. No automatic discovery,
TLS distribution rollout or business retry is supplied.

In A's release IEx, explicitly connect the static deployment allowlist:

```elixir
alias Beamlet.Node.CLI
allowed = ["authority@b.example.internal", "executor@c.example.internal"]
:ok = CLI.connect("authority@b.example.internal", allowed)
:ok = CLI.connect("executor@c.example.internal", allowed)
{:ok, b} = CLI.authority("authority@b.example.internal", allowed)
{:ok, c} = CLI.authority("executor@c.example.internal", allowed)
true = :erpc.call(b, Node, :connect, [c], 5000)
{:ok, catalogue} = Beamlet.Harness.Catalogue.new([Beamlet.Harness.Tools.WorkspaceRead.descriptor()])
# Explicit operator input on A to construct the creation binding. The adapter
# never reads this environment variable, and C needs no provisioned user key.
user_key = System.fetch_env!("BEAMLET_CREATION_KEY")
opts = [id: "operator-demo",
  model: %{provider: "openai-compatible",
    config: %{"base_url" => "https://provider.example/v1", "model" => "operator-selected-model"},
    credentials: %{"api_key" => user_key},
    placement: %{claims: %{"native" => 1}, allowed_nodes: [c]}},
  catalogue: catalogue,
  tools: %{"workspace_read" => %{id: "tree", capability: "read-v1", environment: "tree-v1",
    claims: %{"native" => 1}, allowed_nodes: [c]}}]
{:ok, ref} = CLI.create(b, opts)
{:ok, turn} = CLI.input(ref, "Read marker.txt through workspace_read")
CLI.watch(ref, timeout: 30_000, events: 128)
CLI.status(ref)
CLI.snapshot(ref)
CLI.stop(ref)
```

Watch subscribes/acks/unsubscribes in the same sink process, prints bounded inspect
output (4096 codepoints maximum/event), limits 256 events and a 60-second receive deadline. Agent control calls have
separate 5-second bounds; synchronous terminal output depends on the IEx device.
Input uses Agent's 65536-byte/context/executable-envelope checks, never truncates
executable input. Timeout/event-limit/loss is explicit and does not establish
cancellation. A disconnected watcher does not own Agent lifetime. A fresh watch
gets a snapshot, without event replay. Provider requests are never retried.

Live refs are ephemeral and cannot be serialized as stable IDs for later RPC
sessions. Release `rpc 'IO.inspect(Beamlet.Node.profile("tree"))'` on an executor and
`rpc 'IO.inspect(Process.whereis(Beamlet.Agent.Registry) != nil)'` are suitable
one-shot readiness checks. Keep control refs in one IEx session or use an
operator-owned trusted script evaluated in one RPC; do not invent ID lookup APIs.
For the raw protocol, subscribe with `Beamlet.Agent.subscribe(ref)`, receive
`{:beamlet_agent, ^ref, sequence, {:snapshot, snapshot}}`, and call
`Beamlet.Agent.ack(ref, sequence)` from that sink process.

Delegation and peers use real refs from this same session:

```elixir
{:ok, parent} = CLI.create(b, Keyword.put(opts, :id, "parent"))
Beamlet.Agent.delegate(parent, [%{authority: b,
  options: Keyword.put(opts, :id, "owned-child"), input: "Read marker.txt"}])
CLI.watch(parent)
{:ok, peer} = CLI.create(b, Keyword.put(opts, :id, "independent-peer"))
{:ok, request} = Beamlet.Agent.peer_request(parent, peer, %{"question" => "ready?"})
Beamlet.Agent.inbox(peer)
:ok = Beamlet.Agent.peer_reply(peer, request, %{"answer" => "ready"})
Beamlet.Agent.inbox(parent)
Beamlet.Agent.peer_take(parent, request)
Enum.each([ref, parent, peer], &CLI.close/1)
```

Waiting delegation parents hold no executor slot. Peer lifetimes are independent;
TTL/loss produces observations without replay. Stop freezes advancement and requests
best-effort cleanup. Partition/local DOWN never proves provider rollback or billing
cessation. Teardown: close Agents, `bin/beamlet_node stop` on A/B/C, verify the
service manager and distribution sockets stopped, remove temporary permitted
fixtures and revoke temporary credentials. Do not automatically replay turns.

Workspace provisioning requires a dedicated allowed-content tree with controlled
ancestors/backing writers, preferably OS read-only. Checks reject traversal,
symlinks/nonregular files and bound UTF-8 reads, but are not atomic openat2 confinement.
Hardlinks, mounts, races and hostile local writers are outside this trust boundary.

For a deterministic physical trial without provider spending, copy
`http-fixture.py` to C and run `python3 http-fixture.py --requests 16` there
(loopback TCP18080 only, at most16 requests,30-second accept waits and10-second whole-request deadlines). On C use
the same trusted adapter registration. On A create an Agent with config
`%{"base_url" => "http://127.0.0.1:18080/v1", "model" => "fixture",
"allow_local_http" => true}` and credentials `%{"api_key" => "synthetic-fixture-key"}`.
The endpoint is loopback on the selected executor C; C receives credentials only
in the dedicated model Operation invocation. The fixture never calls a
provider and always requests marker.txt then reports an observation digest. Before
acceptance, compare that digest with SHA256 of the expected Tool JSON content;
a final fixture string alone does not prove successful workspace reading. Inspect
wrong-environment Tool errors separately. Stop the fixture with Ctrl-C during
teardown. The Python fixture has no production application dependency.

The user removed physical acceptance from this MVP's completion criteria.
Physical execution is **untested**. The following is optional deployment guidance. Operator prerequisites: two distinct
physical hosts for B/C, optional third A, compatible release build, reachable
long-name DNS/IPs, private firewall access to EPMD/fixed ports, securely provisioned
shared cookie, an executor-only permitted marker tree and local compatible endpoint
or separately authorized live endpoint/key/spending. No SSH credential discovery or
remote deployment is authorized here. Record host identity and node role on each
host, build hash, exact redacted commands, B authority ref, C-only marker content
observation, concurrent controls, stop, executor disconnect/partition and explicit
no-target/wrong-environment behavior; reconnect never replays. A future physical trial may attach evidence to the physical-acceptance.md task
record. Same-host peers establish automation evidence only.

Optional live smoke is not executed: obtain separate spending/endpoint approval,
supply an Agent HTTPS binding with explicit credentials and run the input/watch example above,
first with empty catalogue then with the permitted marker. Record only normalized
bounded outcome, never raw requests/settings/credentials. This probes that endpoint's
supported subset and makes no general model compatibility claim.

Model migration requires matching builds on every participating node; mixed-version
execution is unsupported. Old `type: :model` profiles, `key_env`, top-level Agent
`api_key`, model collections and switching options fail explicitly. Each Agent has
one immutable provider/config/credentials/placement binding for its lifetime;
create a separate Agent for a different binding. Tools carry empty credentials.
Children require an explicit binding in creation options; peer messages do not
inherit one. No automatic routing, fallback or replay exists.

Bindings and credentials exist as plaintext in authority/executor processes and
transient messages until ordinary cleanup. There is no persistence or secure memory
erasure guarantee or protection from administrator inspection. Generated snapshots,
progress and results omit binding fields; malicious providers can still echo data.
Keep creation options and operator environment out of logs and shell tracing.
