# Daemon-host implementation evidence

## Candidate / ownership

- Approved child `.trellis/tasks/10-17-daemon-host`, status verified in_progress before writes; baseline HEAD `0fed1b1`, branch dev, cwd `/mnt/data/Project/Beamlet`, accepted uncommitted Node-library prerequisite preserved.
- Product/test/spec candidate is **frozen for parent read-only independent check**. Independent check is pending; neither this note nor checked implementation steps attest that review or final parent acceptance.
- Smallest gap: generated daemon had no boot policy while deployment still targeted retired Node executable. One coherent daemon config → Application → one-shot bootstrap → runtime/release/checker seam now owns that policy.
- No edits to accepted Node/Agent/Runtime/Harness/CLI source or tests, Web/runtime/CSP, dependency versions/lockfile, journal or archive. No discovery/session, paid provider, SSH, physical deployment, multi-Node naming, reconnect or business retry work.

## Paths / interfaces

### Daemon

- `apps/beamlet_daemon/mix.exs`: direct Node dependency (no CLI/Web).
- `lib/beamlet/daemon.ex`: replaces generated hello stub with `configuration(settings)` → `{:ok, [enabled: boolean, node: opts, allowed_nodes: names, peers: names]}` or `{:error, :invalid_daemon_configuration}`. Unknown/duplicate host or Node option keys reject. enabled defaults false; default roles authority+executor; both only modes and either ordering of both accepted. Empty/duplicate/interaction/unknown roles reject before role startup. Node.configuration owns resource/provider validation; Cluster.connected owns whole allowlist validation without connecting or atomizing it. Peers are distinct, max32 and a subset of that validated allowlist.
- `lib/beamlet/daemon/application.ex`: default empty tree; enabled starts Node then Bootstrap under host supervisor. No runtime switching/config_change API; one Node per VM remains intentional.
- `lib/beamlet/daemon/bootstrap.ex`: host-owned temporary Task; start_link acknowledges before network work, each peer connects once sequentially through Cluster. Logs only index and connected/unavailable. Failure leaves local service alive; no reconnect or business submission/replay. Cluster retains its existing5s attempt/controller/helper ownership. Entire32-peer list may take about160s; this does not block Application/Supervisor startup. OTP can complete an initiated handshake later, not network rollback.
- `test/beamlet/daemon_test.exs`:4 ordinary tests replace generated doctest/stub test; real empty/default/only trees, invalid host/resource options, bounded peers and safe failure continuation. `test/beamlet/bootstrap_distributed_test.exs`:2 actual named tests assert startup returns while peer net_kernel remains suspended and observe actual task/controller/helper DOWN before resume, on deadline and abrupt host-supervisor loss. `test/test_helper.exs` excludes distributed by default.

### Runtime / release / deployment

- Root `mix.exs`: sole release entry beamlet_daemon replaces old Node release; isolated backend compilation selects five libraries plus daemon, excludes Web/CLI. Runtime path `config/daemon_runtime.exs` replaces removed backend_runtime.exs.
- daemon_runtime reads absolute trusted BEAMLET_CONFIG, accepts only the daemon namespace/settings, validates via Daemon, and explicitly enables host. Reader/validation errors become a static message outside rescue/catch context (no raw exception cause/config inspection). This is trusted executable operator code, **not a sandbox**; code that itself prints/executes is outside sanitization guarantees.
- `scripts/deployment/daemon.example.exs` replaces node.example.exs; only daemon settings, explicit trusted providers/local Tool settings, no user model key. `rel/env.sh.eex` did not need editing: existing shared long-name/fixed-service-port/default9100 and rpc/remote/restart/stop/pid helper port0 branches are preserved and actual RPC/pid/stop collision behavior was verified.
- `scripts/deployment/check-release.sh`: copies one artifact outside checkout/deps, retains SHA256 file manifest/fingerprint, checks .rel/.app/lib closure without CLI/Web/Phoenix/Plug/Bandit/WebSock; then invokes migrated named checker.
- `scripts/deployment/check-named-release.py`: same artifact named-starts default/authority-only/executor-only on9100 and checks real Registry/Provider/Gateway process choices, RPC/pid/stop. Default failed-peer warning/local service continue. Then two only services from same bytes on19101/19102 bootstrap-connect and complete one remote deterministic model turn restricted to executor placement (authority has no Gateway). Eleven malformed runtime/config start cases fail, with static errors and no synthetic sentinel echo.
- `scripts/deployment/check-local.sh`: daemon release replaces old executable; final CLI two-artifact/stdin/reattachment gate explicitly deferred. Full aggregate script was not rerun (individual child gates below were run); it retains parent Dialyzer/Sobelow/xref commands, not claims they passed here.
- `scripts/deployment/README.md`: current service/config/role/connection controls and boundaries; no obsolete Node.CLI or hidden old executable. Preserves bounded HTTP fixture/full Tool-observation digest guidance, explicit credential isolation, workspace trust, uncertainty, no retry, matched-artifact rollback and untested physical/paid boundaries. http-fixture.py and migrated named HTTP/workspace test unchanged.
- Narrow spec updates: backend index/directory-structure/agent-orchestration/error-handling/backend-release. Updated only implemented host/release ownership; discovery/CLI session remain pending.

Full lane path list: `/tmp/beamlet-daemon-evidence/daemon-changed-paths.txt` (19 existing/new paths plus2 removals). Child implement.md and this note are additional artifacts.

## Toolchain / exact validation

Evidence directory: **`/tmp/beamlet-daemon-evidence/`**. OTP29.1.2 / Elixir1.20.4; project dependencies available (`deps.log`); no installs/version updates or explicit tool repair performed. Named Mix runs used scheduler-only ERL_FLAGS='+S 2:2' and explicit securely generated parent --cookie, never printed. Peers inherit the explicit parent cookie through existing Node.get_cookie calls.

| Command / scope | Actual result / retained log |
| --- | --- |
| `mix deps` | passed; deps.log |
| `mix format`, then `mix format --check-formatted` | passed; format-final-apply.log, format-final.log |
| `mix format --check-formatted scripts/deployment/daemon.example.exs` | passed; example-format-final.log |
| `mix compile --force --warnings-as-errors` | passed all8 apps; compile-final.log |
| `mix test --seed 631927` | **171 passed**, including1 doctest;16 distributed excluded; ordinary-final.log |
| Actual named selected regressions below | **16 passed**, zero failures; named-final.log |
| `mix credo --strict` | final97 source files /747 mods-funs, no issues; credo-final.log |
| `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite` | passed; build-final.log |
| `BEAMLET_CHECK_LOG_DIR=/tmp/beamlet-daemon-evidence/copied-final bash scripts/deployment/check-release.sh` | passed closure, three named configurations,5 total successful service boots/RPC/pid/stop (3 modes +2 remote services), one remote turn, failed-peer continuation and11 rejected starts; release-final.log and copied-final/* |
| `env -u SECRET_KEY_BASE MIX_ENV=prod mix run --no-start -e ':ok'` | expected exit1; asserted SECRET_KEY_BASE is missing; web-missing-secret.log |
| Web CSP/controller suite |7 passed within ordinary run; unchanged actual nonce/CSP assertions retained |
| `git diff --check`, `git diff --cached --check` | passed at final inspection |
| Shell `bash -n` for both sh checkers, Python ast.parse for named checker | passed |
| Active source old namespace/boot/runtime/release-entry search in apps/config/scripts/rel/root manifest/README | zero obsolete executable/API matches |
| Active changed-path LSP probe | **inconclusive**,10 Elixir paths; lsp-probe.log/lsp-results.json/lsp-stderr.log/lsp-transcript.json/probe-lsp.py |

Ordinary app breakdown: Harness35 + Actions28 + Runtime30 + Agent4 + Node56 + Daemon4 + CLI7 (1 doctest/6 tests) + Web7 =171. Generated daemon doctest was replaced by behavioral tests, hence1 remaining doctest rather than prerequisite stage's2.

Named invocation (launcher generated cookie without output; unique name):

```sh
ERL_FLAGS='+S 2:2' elixir --sname <unique-node> --cookie <secure-random-cookie> -S mix test \
  apps/beamlet_runtime/test/beamlet/distributed_test.exs \
  apps/beamlet_node/test/beamlet/distributed_test.exs \
  apps/beamlet_node/test/beamlet/delegation_binding_test.exs \
  apps/beamlet_node/test/beamlet/cluster_distributed_test.exs \
  apps/beamlet_cli/test/beamlet/release_integration_test.exs \
  apps/beamlet_daemon/test/beamlet/bootstrap_distributed_test.exs \
  --only distributed --seed 631927
```

Named breakdown Runtime6 + Node7 + Daemon2 + CLI1 =16. CLI1 is the unchanged actual HTTP→workspace→model integration including key/model correlation, full observation digest, wrong environment/no fallback, later turn/fresh capacity, held request stop and executor loss/no replay. Node seven-role coverage remains actual library tree startup, not daemon interaction boot.

### Copied artifact fingerprint

- Final copied-file manifest SHA256: **`1f20167b3ef3f47b6b23b4f23be4a0474a573a56740bb98cc8abd7311d5cc640`** (`copied-final/copied-manifest.sha256` hashed by `copied-final/copied-tree.sha256`). This is a deterministic sorted relative-file/content manifest fingerprint, not a tarball hash.
- Source artifact `_build/backend/prod/rel/beamlet_daemon`; temporary copied tree removed after checks; manifest, .rel, app paths, boot/RPC/rejection logs retained. All role choices used the same bytes, no per-role release builds.
- `_build/backend/prod/lib` inspection contains only6 Beamlet apps + Finch/hpax/Jason/MIME/Mint/nimble_options/nimble_pool/Req/telemetry; no Web/Phoenix/CLI/Plug compiled closure (backend-build-libs.log).

## Failures / diagnoses (original logs preserved)

1. `daemon-initial.log`: initial test compile failed on Elixir keyword-list improper-cons syntax. Corrected test vector to an explicit tuple cons (still improper data); daemon-corrected.log passed4. No product assertion was relaxed.
2. `credo-initial.log`: strict Credo exit10 for nested module alias and excessive nesting in Bootstrap Task closure. Aliased Cluster and extracted Task MFA run/1 (same temporary task/network behavior). Final forced compile/ordinary/named/release rebuilt candidate all passed. Earlier successful build/release/bootstrap logs retained as initial, not confused with final hash.
3. LSP entrypoint itself lacks/lock-mismatches vendored dependencies and did not initialize before25s deadline. Its launcher automatically tried Mix.install/dependency fetch; the probe terminated only its own process group after timeout. No explicit dependency install/repair or project dependency update was run. No path got publishDiagnostics; all10 remain inconclusive, not empty-cache clean. Mutation-triggered partial tool reports do not substitute for complete LSP coverage.
4. Additional synthetic unavailable WorkspaceRead root probe: process exited1 with safe provider_unavailable startup failure and **no synthetic root sentinel in stdout/stderr** (provider-unavailable-probe.log). It wrote a VM crash dump, moved to provider-probe-erl_crash.dump in evidence. No real credentials were used. Operational/provider failure is not recovery/retry evidence.
5. Web missing-secret exit1 is the expected regression assertion, not a failed gate. Existing lifecycle-loss tests emit expected error logs despite passing counts.

## Index / source safety

- Initial snapshots before any writes: status.before, index.before.sha256, worktree.before.sha256, files.before.sha256. Initial staged diff SHA256 **8ef8776a444a467f623d5fa8d5e1016c6106bb3a1a5c8417f3485a0f22c4e66e**.
- Worker ran **no git add/stage/unstage/reset/restore/clean/commit/push/merge/amend/branch operations**. Staged changes existed at entry. During work daemon changes moved into index by an **unknown actor**; parent was notified. Index was preserved, never restored or claimed clean. `noStagedFiles=false`.
- Frozen observation index SHA256 **7c00eaa4d3952100f061c8b91c400064fb8779249e8156566087fe077ff7f416**; status.frozen/index.frozen.sha256/worktree.frozen.sha256 preserve observation before evidence-note writes. Index may be updated externally after observation; this is not a claim of index immutability.
- Frozen product/test/spec manifest `product-test-spec.frozen.sha256`, manifest hash **041dd03b9974f62ccb3e8d32ccc5fa3005b7fe8756fb0168946541892f70b3c0**. Final `sha256sum -c` passed all19 extant lane product/test/spec paths (frozen-bytes-check.log). Parent can validate bytes independent of staging. Initial tracked source comparison changed-from-start.txt shows only lane-owned paths; accepted prerequisite product and other planning bytes preserved.
- After artifact writes, final observation status.final had69 changed paths versus53 at entry; final observed cached-diff hash **d6ae2d7f14ca205a352d49baaf6dfdc9ac5982f4d863c8e457e55c52e1eb9da3** (index.final-observed.sha256), again reflecting external staging. Final whitespace checks passed (diff-check-final.log); active obsolete-reference search empty (obsolete-active-refs.log). Artifact-only edits after this observation do not change frozen product bytes.

## Residual risks / next gate

- **Parent independent read-only check pending.** Product/test/spec frozen; no edits after handoff unless authorized.
- LSP inconclusive due tool startup/dependency failure. No Dialyzer/PLT refresh, Sobelow, cycles or full aggregate check-local rerun in this child; cumulative final static-analysis gates remain parent work.
- CLI standalone release/stdin/discovery/reattachment and final two-artifact acceptance are intentionally deferred. No parent AC completion is claimed.
- Fixed VM-global Node names, trusted distribution/config code, startup-only policy and transient plaintext credential/process exposure remain intentional existing boundaries. One attempt per configured peer; not a cluster manager, rollback guarantee or upstream business cancellation guarantee.
- Same-host named peers/copies are automation evidence only. Physical multi-host deployment and paid/live provider calls remain untested and unauthorized.
