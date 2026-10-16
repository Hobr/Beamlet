# CURRENT child4 independent handoff — local scoped PASS; physical pending

## Final scope disposition — user-approved removal

The user instructed: "取消跨物理主机验收这一要求, 继续开展后续工作".
This supersedes earlier pending/deferred physical-gate statements below. Child AC5
is removed; parent AC2/AC11 require the delivered multi-VM/release/deployment
evidence only. Physical testing was not executed and is not claimed. All remaining
implementation/check gates are accepted (123 ordinary tests;7 distributed tests at
two seeds; copied named release/closure/control checks). No source changed for this
scope reduction. Proceed to Phase3.4 commit plan, then archive/journal bookkeeping.
Earlier records below remain historical where they conflict with this disposition.

Independent review completed with scoped repairs. **No local blocker remains.**
Final123 tests pass (Harness26/Actions5/Runtime28/Agent4/Node53/Web7), and actual
named distributed7/7 passes at seeds719916 and631927 (Runtime4/Node3). CLI5 now
covers malformed options, subscription cleanup, event limits, dead refs and authority
loss. Compile/format/strict Credo/existing-PLT Dialyzer pass; Web secret/CSP preserved.

Build/closure and copied authority/executor eval boots pass without Web/model secrets.
New repeatable check-named-release.py also verifies actual long-name foreground
startup, fixed service port, RPC role assertions and stop with bounded cleanup.
rel env fixes RPC/stop/remote helper eaddrinuse by giving control VMs ephemeral ports.
BEAMLET_CONFIG now rejects relative paths. HTTP fixture has10s whole-request bounds,
malformed-length handling and joined timers; two socket requests and slow-header
teardown pass. Required .app edges/.rel/lib exclude Web/Phoenix/Plug/PubSub/Bandit;
Req optional Plug metadata/helper modules do not ship the Plug application.

Runtime test repair independently reviewed unchanged: post-release executor-clock
lease fence, no cross-machine clock comparison, single submissions and intact
success/no-fallback assertions. Controlled stale capacity proves no_target only for
its probe; original historical terminal reason remains unknown. Former aggregate
local blocker is closed by final independent7/7 runs and saved owning Runtime32.

Physical B/C distinct-host evidence remains pending (childAC5/parentAC2,AC11).
No SSH/private credential/remote deployment/paid provider access. Optional live smoke
was not run. Whole LSP diagnostics remain inconclusive; Dialyzer used existing PLT.
No residual review-owned VMs/fixtures detected. verification.md/check-report.md begin
with current evidence; historical findings/logs remain underneath. Parent owns spec
synchronization, final integration/acceptance, commit/archive. No source/manifest/
lock/core-role/spec/state/index edits outside the authorized child4 seam occurred.

---

# Historical child4 implementation handoff — superseded

Implemented thin Beamlet.Node.CLI controls over actual Agent refs and event credits;
root Node release/backend build selector; separate required trusted deployment runtime
config; long-name/fixed-port release env; deployment examples/runbook and repeatable
local/copy-closure checks. New three-role independent-VM integration executes the
real OpenAICompatible socket path → WorkspaceRead marker → model, verifies
correlation/authority/executor roles, rejects wrong environment without fallback,
stops held HTTP work, and observes executor loss without business replay.

Public CLI: authority(name, trusted_names), connect(name, trusted_names),
create(authority_atom, options), input(ref,text), snapshot/status(ref), stop(ref),
close(ref), watch(ref, timeout: 1..60000, events: 1..256). Watch consumes and acks
from its own sink process, returns terminal snapshot or timeout/loss/event-limit;
no automatic retry. Delegation/peer APIs remain Agent-owned and are documented
using live refs. Runtime boot uses Application env :beamlet_node,:boot from an
absolute operator-owned BEAMLET_CONFIG file (trusted Elixir config, no model injection).

Build with `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_node`.
Artifact at _build/backend/prod/rel/beamlet_node. Copy closure proof and separate
authority/executor boots pass outside source/deps with Web/model secrets unset.
Backend selector avoids Web/Phoenix compilation and optional Req Plug shipping;
ordinary umbrella production compilation did compile Phoenix, recorded separately.
Default Web production missing-secret fails, Web7 including CSP pass unchanged.

Evidence: umbrella120 passed with7 distributed excluded; CLI2; final local HTTP
VM test1 passed seed19278; Node3 distributed passed seed719916. Strict Credo76
files/595 mods-funs, format/compile, existing-PLT Dialyzer0, Sobelow, sibling deps,
release closure/boot and whitespace pass. Full distributed aggregate **6/7 passes**:
Runtime test line78 fails twice in full suite, but Runtime4 passes same-seed focused
recheck. Owning Runtime seam diagnosis/repair/recheck is required before claiming
the integration gate green. No upstream code was changed by child4.

Physical B/C distinct-host acceptance is explicitly pending. Need two physical
hosts, compatible build, resolvable long names/private EPMD+fixed distribution
ports, securely supplied shared cookie, trusted node configs, C-only permitted
marker tree and local fixture or separately authorized provider endpoint/key/spending.
No private credential search/remote deployment or paid call occurred. Runbook and
physical-acceptance.md provide the operator record. Parent completion remains
blocked on physical evidence and independent review, plus upstream aggregate gate.

See verification.md for exact commands/counts/hashes/AC mapping and check-report.md
for blockers/limits. Scope preserved: no Agent/Runtime/Harness/Actions/core role
changes, dependency manifests/lock/spec/task-state/index/staging/commits. Earlier
user dirty work and SBOM commit remain intact. Parent owns independent review,
upstream repair coordination, spec synchronization and final bookkeeping.
