# Backend Client and Release Migration

## 1. Scope / Current stage

Node is now a callback-free, explicitly supervised library. The existing terminal
adapter and its HTTP/workspace integration test belong to CLI:
`apps/beamlet_cli/lib/beamlet/cli/client.ex` and `apps/beamlet_cli/test/beamlet/`.
Trusted cluster naming/connection/filtering belongs to
`apps/beamlet_node/lib/beamlet/node/cluster.ex`. Agent remains the business loop.

Daemon and CLI are opt-in hosts with separate beamlet_daemon/beamlet_cli releases.
CLI owns a foreground command session and uses shared discovery/lookup APIs.
Independent CLI repair review returned READY and parent AC1–AC9 acceptance is
recorded in the parent task's research/final-acceptance.md. The approved commit
batch is recorded separately; archive/journal remain deferred. The old Node release,
backend_runtime.exs and node example
are removed, without compatibility forwarding.

## 2. Current interfaces

```elixir
# In an embedding supervisor's children (one Node per VM):
{Beamlet.Node, roles: [:interaction, :authority, :executor]}

alias Beamlet.Node.Cluster
alias Beamlet.CLI.Client
{:ok, authority} = Cluster.authority("authority@host.internal", trusted_names)
:ok = Cluster.connect("authority@host.internal", trusted_names)
{:ok, nodes} = Cluster.connected(trusted_names)
{:ok, ref} = Client.create(authority, options)
{:ok, turn} = Client.input(ref, "hello")
Client.watch(ref, timeout: 30_000, events: 128)
Client.snapshot(ref)
Client.status(ref)
Client.stop(ref)
Client.close(ref)
```

Delegation and peers use the public Agent APIs with live refs; see
[Agent and Node](./agent-orchestration.md). Agent.list/lookup and Node.Agents.discover provide shared discovery; CLI Session
retains bounded local aliases to live Refs.

## 3. Cluster and terminal contracts

Cluster validates the **whole** trusted allowlist: at most32 ASCII node@host names,
each at most255 bytes. Malformed/oversize/improper lists reject safely. Only a
matching, valid name is atomized by authority/2; arbitrary business strings never
become atoms. connected/1 filters currently connected visible/hidden nodes, plus
the local VM only when distributed and allowlisted; it does not atomize allowed
strings, scan hosts, or connect implicitly. Results are sorted existing node atoms.

connect/2 attempts one connection in an owned helper with a five-second receive
budget; failure/timeout is unavailable. The stream controller cleans its helper
on timeout/caller loss. OTP may complete an already-started handshake later; this
is not a guarantee of network rollback. There is no background reconnect loop or
business retry. A future host may explicitly request another connection.

Client create/input/snapshot/status/stop/close delegate to Agent. Ref remains live
and ephemeral. Watch accepts only a keyword list with timeout/events keys,
timeout1..60000ms (default5000), events1..256 (default64). It subscribes, consumes
and acknowledges from the same sink, then unsubscribes in after. Terminal statuses
done/error/stopped return `{:ok, snapshot}`. It prints at most4096 codepoints per
event using bounded inspect. Its receive deadline excludes bounded Agent control
calls and synchronous terminal IO; it is not a strict whole-call wall-clock bound.
Timeout/event-limit never cancels work. Rewatch gets a fresh snapshot, not event
history; subscriber loss does not own the Agent lifetime.

| Condition | Observation |
| --- | --- |
| Invalid/missing allowlisted name or malformed whole list | invalid_authority |
| Failed/stalled explicit connect | unavailable |
| Malformed/unknown/over-limit watch options | invalid_watch_options before subscribe |
| Event budget exhausted | event_limit; subscription removed |
| Receive deadline/loss | timeout_or_loss, or underlying unavailable during control |
| Dead ref/start failure | public Agent error; no fallback/retry |

## 4. Daemon host, runtime and packaging

Beamlet.Daemon.configuration/1 normalizes enabled/node/allowed_nodes/peers, rejects
unknown/duplicate host and Node option keys, and delegates resource/provider
validation to Node.configuration/1. enabled defaults false; node.roles defaults
[:authority, :executor]. Only [:authority], [:executor] or either ordering of both
are valid. Empty, duplicate, interaction and unknown roles reject before any role
starts. No runtime reconfiguration/role switching API exists. A fixed-name Node
still means one tree per VM, not simultaneous enabled hosts in the umbrella.

Daemon.Application explicitly supervises Node then a temporary Bootstrap Task when
enabled. The task connects distinct peers (max32, subset of validated allowed_nodes)
sequentially once via Cluster. Network completion does not block Supervisor.init.
Each attempt has Cluster's five-second helper budget; a full failed list can take
approximately160s. Logs contain only index and connected/unavailable, never names,
raw errors or config. Failure leaves local service available. Task/controller/helper
ownership is cleaned on host loss/deadline; an initiated OTP handshake may complete
later. No background reconnect or business replay exists.

BEAMLET_BACKEND_BUILD=1 compiles the seven backend libraries (five core,
`beamlet_storage` and `beamlet_i18n`) plus both hosts under isolated _build/backend,
excluding Web. Each release excludes the other host. beamlet_daemon uses daemon_runtime.exs,
which reads trusted operator-owned absolute BEAMLET_CONFIG, accepts only the daemon
namespace/settings, normalizes/validates, then explicitly enables the host. Reader
and validation failure raises one static message outside the rescue context; raw
config/cause/credentials are not inspected. Trusted Elixir code can itself leak or
execute arbitrary actions; this is not a sandbox. Ordinary Web production
SECRET_KEY_BASE failure and CSP remain unchanged.

rel/env.sh.eex retains long-name service fixed BEAMLET_DIST_PORT (default9100)
and ephemeral port0 for rpc/remote/restart/stop/pid helpers. Eval alone does not
prove this regression. check-release.sh verifies copied .rel/.app/lib closures
without Web/Phoenix/Plug/Bandit/WebSock, the opposite host, or the presentation-only
`beamlet_i18n`/`gettext`/`expo` set (the daemon must never ship them; the CLI release
legitimately does). check-named-release.py uses the same
artifact for default/authority-only/executor-only named start/RPC/pid/stop, then
authority→executor bootstrap and a deterministic remote Gateway turn. It checks
failed-peer local continuation and static malformed-config rejection. Copied-file
manifest/hash and logs are retained in a printed evidence directory, overridable
with BEAMLET_CHECK_LOG_DIR. Ports9100/19101/19102 must be free. Seven combinations
remain library tests, not daemon modes or role-specific build artifacts.

Deployment instructions/example are under scripts/deployment (daemon.example.exs).
The unchanged bounded Python HTTP fixture and migrated CLI integration retain
complete Tool-observation digest/correlation, wrong environment, fresh capacity,
held-request stop and executor loss/no replay. check-local runs both release
builds and copied/stdin/reattachment gates; final parent evidence is recorded separately. Rollback
requires an old artifact with its matching config/protocol; restart is not Agent
recovery. No physical deployment or paid provider evidence is implied.

## 5. Durable storage in the packaged hosts

`storage:` is an optional trusted operator block in the daemon `BEAMLET_CONFIG`
only; the daemon release ships `beamlet_storage`/Ecto/Exqlite/Postgrex in its
closure and opens exactly the datasets the configured roles need. The CLI host is
fixed interaction-only: no database, no storage key, release entrypoint unchanged.
`Beamlet.Storage.Host.status/1` reports durable admission (a live format check plus
a real rolled-back write) separately from Node/Repo readiness; durable
submit/accept are refused while it is off, and recovery re-admits on a fresh probe
without a restart. Migration is the explicit `mix beamlet.storage.migrate` (or
`Beamlet.Storage.Operator.initialize/2` via release `eval`) operator action; boot
never migrates, creates or repairs a dataset. `$REL start` is foreground and
`$REL rpc` is unusable in this environment; probe with a separate
`erl -name ... -setcookie ... -eval 'rpc:call(...)'` node.

## 6. Tests and evidence boundaries

Preserve the migrated Client malformed-option, cleanup/event-limit, dead-ref,
watch/ack and authority-loss tests. CLI's named distributed integration must retain
three independent roles, real HTTP→workspace→model correlation, wrong environment
without fallback, a subsequent turn after fresh capacity, stop during a held
request, and executor loss without replay. CLI owns its necessary test fixture and
direct test dependencies; Node must not depend on its CLI consumer.

Node tests start/stop all seven role combinations explicitly and execute a local
model turn with all three roles, without terminal input. Library/CLI loading starts
no Node/Agent/Executor services. Cluster tests cover exact name/list limits,
non-atomization, explicit named connection/filter/disconnect and a stalled handshake.
Run named tests explicitly; ordinary helpers exclude distributed tests.

For local named runs use ERL_FLAGS='+S 2:2' and explicit parent --cookie with a
secure temporary value (never print it); peers already pass Node.get_cookie().
Putting -setcookie in inherited ERL_FLAGS was observed to cause parent/peer cookie
mismatch; retain failed and corrected logs separately.

Node-library independent review accepted this library seam with no actionable
P0/P1/P2 findings: retained logs show169 ordinary (including2 doctests) and14
actual named tests, plus format, forced warning-fatal compile and strict Credo.
Independent fresh-VM startup and suspended-peer probes verified no automatic roles
and actual connection controller/helper DOWN on caller loss/deadline before peer
resume. These two probes are review evidence, not checked-in regression tests;
preserve or add equivalent assertions when changing those seams. This acceptance
does not cover new host/release artifacts or final parent static-analysis gates.

Prior provider-migration evidence (161 ordinary/12 named distributed, copied old
release gates, existing-PLT Dialyzer) is historical, not proof for the new host
artifacts. Current stage evidence lives in the node-library task research note.
Active LSP timeout/unavailability is inconclusive, not clean. Physical multi-host
and paid provider execution remain untested and are not claimed.

Daemon-stage regression evidence is recorded separately in
`.trellis/tasks/archive/2026-10/10-17-daemon-host/research/implementation-evidence.md`; prerequisite
Node evidence above is not proof of this new release. Daemon tests assert empty
ordinary startup, all three actual trees, safe invalid host/resource rejection,
failed-peer continuation and actual startup task/controller/helper DOWN while a
peer remains suspended, both on deadline and host loss.

Daemon independent acceptance resolved two startup/checker regressions: Node must
validate common Runtime limits for every role set before returning children, and
copied-service cleanup must attempt both services even when the first stop fails.
Preserve the original startup/RPC exception and every nested cleanup note so a
failed fallback wait remains visible in the final traceback. The six Python
fault-injection regressions cover stop/timeout/nonzero, fallback failures and
composed multi-service failures with and without an original RPC exception.
Deployment checks require Python3.11+ (`sys.exception`/`add_note`). Final independent
review verified all six tests plus the original composed probe; daemon acceptance
does not attest pending parent static-analysis or CLI integration gates.

## Foreground CLI host

The final CLI host is opt-in (`Beamlet.CLI.configuration/1`), fixed interaction;
ordinary Application loading has an empty supervisor and no terminal loop.
`Command` parses bounded UTF-8 lines, `Session` dispatches to Cluster/Agent/Agents,
and `Renderer` limits display and sanitizes arbitrary error terms. `Runner` owns
stdin and VM exit after startup; tests inject read/output/exit callbacks. The
standalone release start entry invokes Runner, while RPC/eval remain control tools.
Creation reads absolute trusted executable Config under `:beamlet_cli,
:agent_options`; host config accepts enabled/allowed_nodes only. No generic eval
command or credential echo. At most128 real Ref aliases; no alias replacement,
implicit attach input, business replay or Agent closure on quit/EOF/detach.
Only successful explicit close removes aliases for that Ref. Watch remains in the
same subscribe/ack sink with existing limits and injectable output.

Root backend compilation includes both hosts; each `mix release` closes over its
own dependencies. CLI excludes daemon/Web and daemon excludes CLI/Web. Both use
host-specific runtime Config and preserve named service/control port policy.
Deployment checks cover copied closure, same-daemon three modes, and independent
foreground CLI sessions with identity retained across quit and EOF. Validation
counts/fingerprints belong in current CLI research evidence, not historical gates.

CLI uses installed Owl0.13.1 for help/nodes/identity/status/discovery tables,
terminal output and display truncation. Owl table width is explicit to preserve
identity columns; bounded cells wrap. Discovery displays at most8 identities with
explicit shown/total counts and completeness/failures; queries remain bounded and
full safe identities of shown entries remain visible. Owl.IO.input is unsuitable
for exact bounded executable lines/EOF (unbounded gets + trim/retry), so Runner
retains a narrow bounded raw-byte reader. Independent repair review accepted the
frozen candidate; final acceptance records distinguish historical failures,
recorded full gates and fresh focused independent proofs.

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

## Scenario: maintain the foreground CLI boundary

### 1. Scope / Trigger

Use when changing Runner transport, Command identity grammar, Session discovery
retention, Renderer layout or copied CLI checks. Owl owns presentation; exact
bounded executable input and live Ref identity belong to the application.

### 2. Signatures

```text
agents [authority]
agents-page N
attach authority id64:dHdvIHdvcmRz safe_alias
input safe_alias exact UTF-8 text
```

The attach example addresses ID `two words`. Creation still reads trusted
absolute Config with `:beamlet_cli, :agent_options`; release host configuration
uses `BEAMLET_CONFIG`, with no generic command eval.

### 3. Contracts

Retain at most65536 raw line bytes before complete UTF-8 validation; LF delimits
commands. Preserve partial EOF and executable spaces. Restore a terminal's
original encoding in after before returning to dispatch/output. This reader must
exclusively own the terminal; nonterminal IO options stay unchanged.
Retain one bounded discovery observation, replace it only on explicit refresh,
and traverse eight full identity rows per page without requery. Invalid refresh
clears retention. `complete` describes query targets, not display pagination.
Encode the entire UTF-8 ID using standard unpadded Base64url after `id64:`;
validate the decoded1..128-byte contract. Saved aliases never rebind after ID reuse.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Malformed UTF-8, native read error or line overflow | Static read error; exit1; no partial dispatch |
| EOF or quit | Exit0; leave Agent alive |
| Invalid/empty/oversize/non-UTF8 encoded ID | Reject before lookup; no eval |
| Page absent, invalid or outside captured range | Safe command error; no implicit query |
| Snapshot becomes stale / ID reused | Explicit attach chooses current ID; saved Ref stays original |

### 5. Good/Base/Bad Cases

Good: copy a full displayed token, attach with a safe alias, then input explicitly.
Base: refresh agents once and traverse the retained observation with agents-page.
Bad: infer input success from terminal echo, hide later identities, or split legal
IDs with shell-like assumptions that narrow the shared library contract.

### 6. Tests Required

Assert returned binary equality through a real PTY for accent/CJK/emoji/combining
text, invalid byte sequences, EOF/partial EOF and65536-byte/overflow boundaries.
Assert exact IO options restored on success/error/EOF. Use a raw PTY for large
boundaries to avoid the kernel canonical-line cap. A copied named CLI must emit
a model-produced marker absent from input, rather than relying on terminal echo.
Traverse more than eight unique live IDs, retain stable ordering without another
query, and test explicit refresh and partial-result labels. Roundtrip whitespace,
quotes, backslash, Unicode/control/NUL/reserved-prefix/max-size IDs to exact Refs;
reject malformed tokens. Verify stale aliases after reuse and Agent survival on
quit/EOF. Execute installed and copied Owl beams: 日本=4, 😀=2, é=1 columns;
assert Ucwidth closure and preserve the separate4096-codepoint event limit.

### 7. Wrong vs Correct

Wrong: call IO.binread against Unicode terminal mode and assume the bytes are
original UTF-8; validate a Unicode-decoded pipe after replacement already occurred.
Correct: bounded raw-byte transport, complete UTF-8 validation, terminal-only
encoding setup/restore and exact-byte PTY plus pipe regressions. Preserve failed
candidates and logs separately from accepted evidence; LSP cache absence is not proof.
