# CURRENT independent child4 verification — local scoped PASS

## Final scope disposition — user-approved removal

The user instructed: "取消跨物理主机验收这一要求, 继续开展后续工作".
This supersedes earlier pending/deferred physical-gate statements below. Child AC5
is removed; parent AC2/AC11 require the delivered multi-VM/release/deployment
evidence only. Physical testing was not executed and is not claimed. All remaining
implementation/check gates are accepted (123 ordinary tests;7 distributed tests at
two seeds; copied named release/closure/control checks). No source changed for this
scope reduction. Proceed to Phase3.4 commit plan, then archive/journal bookkeeping.
Earlier records below remain historical where they conflict with this disposition.

Independent source/diff/script review completed 2026-10-16 on
`feat/distributed-agent-mvp`, HEAD `ecd61e6a2e3b6a10df2484ff7867bc90fb88e800`.
No local blocker remains. Physical B/C distinct-host gate is pending; live-provider
smoke was not run. The historical blocked implementation record below is superseded.
Toolchain: Elixir1.20.4/OTP29; commands from root with `ERL_FLAGS='+S 2:2'`.

## Independent gates

| Exact command (after ERL_FLAGS above) | Result and saved log |
| --- | --- |
| `mix test apps/beamlet_node/test/beamlet/cli_test.exs --seed 631927` | 5 passed, `/tmp/child4-independent-cli.log`; final assertions also covered by full run below |
| `mix test --seed 631927` | **123 passed**: Harness26/Actions5/Runtime28/Agent4/Node53/Web7; 7 distributed excluded. `/tmp/child4-independent-tests-final.log` |
| `elixir --sname independent_child4 --cookie <isolated-fixture-cookie> -S mix test --only distributed --seed 719916` | **7 passed**, Runtime4+Node3; `/tmp/child4-independent-distributed.log` |
| `elixir --sname independent_child4_final --cookie <isolated-fixture-cookie> -S mix test --only distributed --seed 631927` | **7 passed**, Runtime4+Node3; `/tmp/child4-independent-distributed-final.log` (123 nondistributed excluded) |
| `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_node --overwrite` | Final build passed; `/tmp/child4-independent-build-final.log` |
| `bash scripts/deployment/check-release.sh` | Final PASS: .rel/.app required dependencies/lib closure, copied eval role boots, copied named authority/executor startup + RPC + fixed19101 port assertion + stop, relative config rejection. `/tmp/child4-independent-release-final.log` |
| `mix format --check-formatted` | Passed; `/tmp/child4-independent-format-final.log` |
| `mix compile --warnings-as-errors` | Passed; `/tmp/child4-independent-compile-final.log` |
| `mix credo --strict` | 76 files/603 mods-funs, zero issues; `/tmp/child4-independent-credo-final.log` |
| `mix dialyzer` | Existing PLT, 0 errors/skips; `/tmp/child4-independent-dialyzer.log`; no PLT refresh |
| `env -u SECRET_KEY_BASE MIX_ENV=prod mix run --no-start -e ':ok'` | Expected nonzero exit with SECRET_KEY_BASE missing; `/tmp/child4-independent-web-secret.log`; Web7/CSP passed above |
| `python3 /tmp/child4-independent-fixture.py` | 2 real POSTs (tool_calls/stop), malformed length400, incomplete headers socket closed within12s, worker joined/socket closed; `/tmp/child4-independent-fixture-final.log` |
| `bash -n scripts/deployment/check-local.sh scripts/deployment/check-release.sh rel/env.sh.eex` | Passed; Python ast.parse syntax checks passed for both changed Python scripts |
| `git diff --check`; `git diff --cached --name-only` | Passed; index empty |

Final copied named regression is repeatable through
`scripts/deployment/check-named-release.py`, invoked by check-release.sh. Each
foreground service has bounded readiness/RPC/stop/wait and forced process cleanup.
Final process scan `/tmp/child4-independent-residual-processes.log` is empty: no
review-owned named service/peer VM remains. Python fixture thread/socket joined/closed.
No complete LSP sweep is available: **inconclusive**. Actual write feedback flagged
an import order issue in the new Python script; imports were reordered. AST/shell
checks pass; these do not constitute a full LSP claim. Existing saved Sobelow/xref/
production-dependency logs in the historical section remain applicable to unchanged
seams; they were not rerun.

## Findings fixed and intermediate evidence

1. **Release defect:** fixed service port was inherited by hidden RPC/stop helpers,
   causing `register/listen error: eaddrinuse`. Initial manual copied-start probes
   failed; their first assertions omitted stderr (probe harness gap). Captured
   `/tmp/child4-independent-named-release.log` established the concrete collision.
   rel env now uses ephemeral port0 for rpc/remote/restart/stop/pid, preserving the
   fixed service listener. Final durable script exercises real named start/RPC/stop.
2. CLI non-keyword/unknown watch options previously raised or were ignored; they
   now return invalid_watch_options before subscription. Added cleanup/event-limit/
   authority-loss/dead-ref coverage, retaining Agent as the only orchestration loop.
3. Runtime config now enforces its documented absolute trusted BEAMLET_CONFIG path.
4. Python fixture now bounds whole requests including slow headers to10s, joins its
   timer, rejects malformed Content-Length, and handles expected socket termination.
   First smoke's early client close caused BrokenPipe traceback (harness behavior,
   `/tmp/child4-independent-fixture.log`); final complete-read smoke passes cleanly.
5. Intermediate umbrella run had122/123 pass because the new loss test expected
   timeout_or_loss only; authority loss during ack legitimately returns unavailable.
   Test now accepts either explicit loss outcome; final123 passed. Preserved log:
   `/tmp/child4-independent-tests.log`. No upstream source defect was implicated.
6. Historical implementation table corrected to Harness26/Actions5 (previously
   reversed); historical counts are retained and not relabeled as independent runs.

## Runtime repair and acceptance mapping

Read actual Runtime distributed test and gateway/directory ordering against accepted
specs/handoffs and aggregate-runtime-repair.md. Fence timestamp and report lease are
both executor monotonic time; the3s wait deadline is local. Gateway full capacity /
zero tasks precedes the fence; eligible Directory lease must be strictly newer.
Held worker/report suspension exercises stale capacity; try/after resumes endpoint.
Each business operation submits once; success/node/stale-result/remote-owner guard/
no-target/no-fallback assertions remain. No Runtime test/source edits in this review.
Controlled stale-capacity probe establishes no_target for that ordering; **historical
failure reason remains uncaptured/unknown**. Saved owning repair Runtime32 and
independent aggregate7/7 across both seeds close the former local aggregate blocker.

Child AC1–AC4/AC6 local portions pass: thin CLI/credits/bounds, backend isolation,
Web secret/CSP preservation, actual three-role VM HTTP→workspace→model correlation,
wrong environment no fallback, stop and executor loss/no replay. Malformed adapter
and whole-batch logic remain covered by accepted Harness/Node tests in123. ChildAC5
and parentAC2/AC11 physical portions remain pending; no physical/live evidence is
inferred. Req.app retains optional Plug metadata/Req.Plug helper modules; Plug app
and artifacts are absent, and required .app dependency edges exclude Plug. .rel and
all shipped lib/.app names exclude Web/Phoenix/PubSub/Plug/Bandit/WebSock apps.

Write scope: CLI, CLI tests, backend runtime config, rel env, deployment check-release,
new check-named-release, HTTP fixture/runbook and these three child reports only.
Root definition, core role/provider code, Runtime/Agent/Actions/Harness, manifests/
lock/specs/state/index and user SBOM HEAD preserved. Parent owns spec synchronization,
final integration acceptance/commit/archive. No SSH/private credential/remote deploy/
paid request. Watch receive deadline excludes bounded Agent control calls and
synchronous terminal IO; runbook now says so. Workspace/partition/provider rollback
and hard-RSS limitations remain unchanged.

## Final SHA256

```text
360258a0ade4d03c05586ae886d9e10f28c7bd48b1214afadb9c8ffce46d83f7  mix.exs
f1f56e0f22d7fcb97735eaf32f972e457b4db2d874fefcf754d7fde2d852896c  config/backend_runtime.exs
3047a594e4da5a59545369de76ea5438fbf12928897d2a129e899b10800727d1  apps/beamlet_node/lib/beamlet/node/cli.ex
1dfdedef54f3f857239f25c55bdd0e56ea07d7f7752575f6049939a1575a0998  apps/beamlet_node/test/beamlet/cli_test.exs
0b0b36d48490c0db2836664000d99eec49bf5c518f48b6c2bcbcec7296059fc1  apps/beamlet_node/test/beamlet/release_integration_test.exs
8240cc770d01de1a09a338dd8ec75657d1e8ccc597ffe7e6364d7d15e773e734  apps/beamlet_runtime/test/beamlet/distributed_test.exs
696f3c536b77bae6c1420cfc15b612529c4b00d3dbfd6cc8f4fc91ba27447875  rel/env.sh.eex
ea6d786cd9068e3500c44c8c55ab99b34d6eb433bf31004ceeb4491de55e0765  scripts/deployment/check-release.sh
aa95c47ccd8adc0ea9a1b0a9890e0158e1f2131bc1ae47093fdc3ea40caa2f1b  scripts/deployment/check-named-release.py
7bbbb701df318fdb6310417a9aa81ada288b6ad1d540ae595a52fe4b2a6eb92d  scripts/deployment/http-fixture.py
a6e81cba36ec8f95090866a18616d8e6b92d96551f36c2b18e7ac2728fe74b15  _build/backend/prod/rel/beamlet_node/releases/0.1.0/beamlet_node.rel
```

---

# Historical implementation verification — superseded

Date: 2026-10-16. Toolchain Elixir1.20.4 / OTP29 (release ERTS17.1.1).
All commands from repository root, `ERL_FLAGS='+S 2:2'` unless stated. Logs below
are actual /tmp artifacts, not prospective gates. No staging/commits/task-state/
spec/upstream manifest/core edits. Prior dirty work and SBOM commit preserved.

| Command | Actual evidence |
| --- | --- |
| `mix test apps/beamlet_node/test/beamlet/cli_test.exs` | 2 passed seed167371, /tmp/child4-cli.log |
| `mix test` | 120 passed: Harness26/Actions5/Runtime28/Agent4/Node50/Web7, 7 distributed excluded; seed291728, /tmp/child4-tests.log |
| `elixir --sname child4_http_final --cookie <isolated-fixture-cookie> -S mix test apps/beamlet_node/test/beamlet/release_integration_test.exs --include distributed` | 1 passed seed19278; /tmp/child4-http-final.log; three independent role VMs, real local HTTP adapter, marker Tool correlation, wrong environment no_target, stop while HTTP held, executor loss/error/no replay |
| `elixir --sname child4_distributed_final --cookie <isolated-fixture-cookie> -S mix test --only distributed --seed 719916` | **6/7 passed**, Runtime3/4 and Node3/3; upstream Runtime test line78 expected :ok got :error. /tmp/child4-distributed-final.log. Same failure initial full run /tmp/child4-distributed.log |
| `elixir --sname child4_runtime_recheck --cookie <isolated-fixture-cookie> -S mix test apps/beamlet_runtime/test/beamlet/distributed_test.exs --only distributed --seed 719916` | Runtime4 passed, same seed; /tmp/child4-runtime-recheck.log. Focused success does not erase two full-suite failures |
| `mix format --check-formatted` | Passed /tmp/child4-format-final.log |
| `mix compile --warnings-as-errors` | Passed /tmp/child4-compile.log |
| `mix credo --strict` | Final76 files/595 mods-funs, zero issues /tmp/child4-credo-final2.log. First run two alias suggestions repaired in owned test |
| `mix dialyzer` | Existing PLT up-to-date, 0 errors/skips, /tmp/child4-dialyzer.log. No PLT refresh performed |
| `mix sobelow` | Scan complete, no findings, /tmp/child4-sobelow.log |
| `mix xref graph --format cycles` | Three existing module cycles: Web4, Agent3, Runtime2; /tmp/child4-cycles.log. These are module cycles, not sibling application cycles |
| `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix deps.tree` | Acyclic sibling dependency direction preserved, no Web/Plug in backend closure; /tmp/child4-deps.log |
| `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_node --overwrite` | Passed /tmp/child4-backend-build-final.log; selector omits Web and Phoenix listener and uses isolated build path |
| `bash scripts/deployment/check-release.sh _build/backend/prod/rel/beamlet_node` | Passed /tmp/child4-closure-final.log: .rel/.app/lib inspected; copied release outside source/deps; authority and executor boots without SECRET_KEY_BASE/BEAMLET_MODEL_KEY, role service assertions and no Phoenix/Web module |
| `env -u SECRET_KEY_BASE MIX_ENV=prod mix run --no-start -e ':ok'` | Expected failure SECRET_KEY_BASE missing, /tmp/child4-web-secret.log. Web files/CSP unchanged, all7 Web tests passed |
| `git diff --check` / `git diff --cached --name-only` | Passed whitespace / index empty |
| Deployment Python fixture socket smoke / `bash -n scripts/deployment/check-local.sh scripts/deployment/check-release.sh` | Passed: imported stdlib fixture, two real loopback POST requests normalize tool_calls then stop; joined fixture worker/closed socket. Shell syntax clean. Python editor clean after correcting overridden log_message signature |

Initial ordinary umbrella production release compiled Web/Phoenix and shipped
optional Plug via Req. Backend build selector repaired packaging within authorized
root scope; isolated backend build excludes these artifacts. Initial copied boot
also exposed release runtime import_config being disabled; use Config.Reader.read!
on the trusted external operator config, then apply settings. No default Web secret
validation change. Intermediate logs: /tmp/child4-release.log,
/tmp/child4-release-final.log, /tmp/child4-closure.log, /tmp/child4-backend-build.log.

Active editor feedback: CLI and integration test Elixir clean; shell and Markdown
assets clean. Backend runtime config editor evaluation reports BEAMLET_CONFIG
missing when no deployment environment is supplied; actual copied-release execution
with the required file passes. No complete standalone LSP sweep is exposed, so
whole changed-path diagnostics are inconclusive, not asserted clean.

## Parent/child evidence mapping

| Criteria | Disposition |
| --- | --- |
| Child AC1 / parent AC9,R6 | CLI explicit authority/create/input/watch/snapshot/status/stop/close; sink acknowledgements, bounded events/output/waits; focused2 and HTTP integration |
| Child AC2 / parent AC10,R1,R2 | Backend release closure/copy/role boot passed; combined Gateway behavior remains covered by accepted Node tests |
| Child AC3 / parent AC10 | Default prod missing-secret failure and Web7/CSP pass |
| Child AC4 / parent AC2 local portion,AC6 | Node3 distributed pass including new real HTTP three-role VM test, stop/loss/no wrong workspace fallback and cleanup. Physical portion excluded |
| Child AC5 / parent AC2,AC11 | **Pending physical evidence**; physical-acceptance.md and runbook list exact prerequisites |
| Child AC6 / parent AC5 | Local real HTTP adapter+workspace test passes; accepted Harness HTTP edge cases in umbrella tests; optional live smoke documented and NOT run |
| Parent AC1,AC3,AC4,AC7–AC9 | Accepted upstream handoffs preserved; sibling deps checked; full distributed Runtime failure remains integration blocker |
| Parent AC12 | Static/compile/format/umbrella/security/release gates pass; distributed aggregate fails; parent independent review pending |

## Hashes (SHA256)

```text
360258a0ade4d03c05586ae886d9e10f28c7bd48b1214afadb9c8ffce46d83f7 mix.exs
cf2cee64c95e12e083e237c657f371888dcdf350909616dd04203f4bab9be1a0 config/backend_runtime.exs
18869f3e020085a0d5eada8905cfb5f329b63566eda92f14664b17066b13632d apps/beamlet_node/lib/beamlet/node/cli.ex
43c089784ec62d60056e6ebec7b85b007fa92b12af582ec0a7e6120a6454c819 apps/beamlet_node/test/beamlet/cli_test.exs
0b0b36d48490c0db2836664000d99eec49bf5c518f48b6c2bcbcec7296059fc1 apps/beamlet_node/test/beamlet/release_integration_test.exs
59017e818f072813d84762bc7a62e3b1b42dbe4bdd6bac423d29b2922f9a2a38 rel/env.sh.eex
6a4a25eb9f1938f3200fb70e0202dafce573ce5f8abab37e98e9c7fd1a731c77 scripts/deployment/check-release.sh
a6e81cba36ec8f95090866a18616d8e6b92d96551f36c2b18e7ac2728fe74b15 built releases/0.1.0/beamlet_node.rel
```

Residual limits: no physical-host or live/paid-provider evidence; trusted workspace
is not an OS sandbox; best-effort stop/loss is not upstream rollback; finite retained
application data is not a hard RSS bound. No SSH/private credential access. The
check-local.sh orchestrator is provided but not invoked wholesale (its component
commands were executed above, with a known failing distributed gate). It intentionally
stops on any failed gate and preserves /tmp logs for operator review.
