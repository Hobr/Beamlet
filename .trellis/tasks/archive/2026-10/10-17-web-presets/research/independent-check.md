# Independent Web host/preset review

Review result: **PASS after fixes for the present Web host/preset scope. No remaining blocker identified for PA1–PA5.** This is an engineering review recommendation, not child or parent final acceptance. Parent owns shared-spec synchronization, integration and acceptance. Future LiveView implementation must honor the caller-loss limitations below.

## Scope and preservation

Loaded child check.jsonl and its ten spec/research entries, child prd.md/design.md/implement.md, parent design (including §§2/3/5), current-capabilities research and implementation-handoff.md. Reviewed actual source of all 15 candidate paths, including untracked files, plus current tracked diff and public Agent/Discovery/ModelBinding/Caller, Node/Cluster and Harness contracts. Did not infer implementation from handoff alone.

Complete candidate inventory:

1. apps/beamlet_web/HOST.md
2. apps/beamlet_web/lib/beamlet_web/agents.ex
3. apps/beamlet_web/lib/beamlet_web/handles.ex
4. apps/beamlet_web/lib/beamlet_web/host.ex
5. apps/beamlet_web/lib/beamlet_web/host/bootstrap.ex
6. apps/beamlet_web/lib/beamlet_web/presets.ex
7. apps/beamlet_web/priv/examples/host.exs
8. apps/beamlet_web/test/beamlet_web/bootstrap_distributed_test.exs
9. apps/beamlet_web/test/beamlet_web/host_distributed_test.exs
10. apps/beamlet_web/test/beamlet_web/host_test.exs
11. apps/beamlet_web/test/beamlet_web/presets_test.exs
12. apps/beamlet_web/test/support/host_peer.ex
13. apps/beamlet_web/lib/beamlet_web/application.ex
14. apps/beamlet_web/mix.exs
15. apps/beamlet_web/test/test_helper.exs

Review changed only HOST.md, handles.ex and host_test.exs, plus this authoritative report. No core, shared-spec, future sibling UI, task-pointer, branch, staging, reset, commit or archive operation. Original modified tracked-file SHA256 values all match review-entry inventory. Binary index diff exactly matches entry state. Actual current staged diff is empty (0 bytes); handoff's noStagedFiles=false claim was not supported by the index observed in this review. Nothing was staged or unstaged.

Independent logs and temporary probes: /tmp/beamlet-web-presets-review. Existing implementation logs were preserved in /tmp/beamlet-web-presets-inventory, and copied-release artifacts in /tmp/beamlet-release-logs.FNx3Xy.

## Findings, evidence and remedies

### F1 — P1, fixed: navigation failure discarded confirmed create feedback

Source: handles.ex:8 (remember), agents.ex:21 (post-start navigation call); fetch had the same process-exit boundary. A missing/stalled Handles process caused GenServer.call to exit after Agent.start had returned a real Ref. The create caller died before returning the confirmed identity or dispatching the initial input. This contradicted the documented separation of creation, navigation and input.

Reproduced before repair using the new navigation-absence regression: navigation-before.log, exit **2**, 1 failure/10 excluded. Traceback identifies agents.ex:21 and a real created PID/Ref. Kept the failed evidence.

Remedy: narrowly catch process-call exits in Handles.remember/fetch and return the static {:error, :unavailable}. Do not catch/retry Agent business operations, recreate or close the instance. Add two permanent regressions in host_test.exs:193 and :222. With Handles absent or still suspended through its five-second call timeout, create returns the confirmed Ref, navigation unavailable, and the genuine 1024-byte executable ceiling rejects the 2000-byte initial task. Trace barriers prove exactly one start and one input, with no extra call. Absent navigation can be restarted and the exact surviving Ref reattached; fetch absence is safe. Suspended navigation is resumed only after the outcome/assertions. Final Web gate passes both.

A timed-out insertion can execute later; the stored object is bounded identity data only. This does not imply mailbox rollback or atomic cancellation.

### F2 — P2 documentation defect, corrected; public-core limitation escalated

Source: former HOST.md statement that calls are bounded by public Agent control calls; actual Agent.start_local/1 invokes DynamicSupervisor.start_child without a finite admission timeout. Remote start uses five-second erpc and input uses five-second GenServer calls, but local create has no whole-call deadline.

Independent executable probe suspended Beamlet.Agent.Agents, observed the create caller still alive after 5200ms, killed it and observed actual DOWN before resuming admission. After resume, one idle Agent was discoverable, exact lookup succeeded and navigation attached it. Caller death did not retract the queued creation. No input was submitted by the dead create caller. This is public-core behavior, not repaired or disguised by a Web timeout/retry change. Reported to the parent through the orchestration channel.

HOST.md now states exact boundaries, mandates owned callers and explicit future UI deadlines/exit handling, and retains uncertain creation for explicit discovery rather than retry. This limitation does not block the present adapter/host deliverable: there is no current LiveView command caller and no bounded whole-create API promise remains. A future UI must not run creation in its event callback or infer cancellation from helper death. Any stronger core admission guarantee needs its own core scope.

### F3 — availability/caller contract, recorded; no new blocker

Presets.describe/reset/resolve are ordinary GenServer calls. Missing Presets exits the caller before Agent.start dispatch; this is adapter unavailability rather than invalid user data or uncertain business acknowledgement. Independent owner-absence probe caught that exit and confirmed public Agent.list was empty. Documented for future helpers; did not introduce a broad exception normalizer that could erase confirmed-created state.

## PA evidence

| Criterion | Assessment and evidence |
| --- | --- |
| PA1 | PASS. Disabled Host has no children, roles, Registry, Gateway, Presets or Handles, with unchanged connected peers and live endpoint. Direct dependencies remain library APIs; no CLI/daemon startup or network provider callback. Four interaction-containing subsets are exercised as actual trees. Actual named interaction-only host connects a configured remote authority/executor and completes a deterministic model turn there. Bootstrap tests suspend peer net_kernel and observe startup task/controller/helper DOWN on deadline and Host loss before peer resumes. One temporary bootstrap per startup, sequential distinct validated peers; failure keeps services alive, no business retry. |
| PA2 | PASS. Immutable configuration/resolver/reset; private model binding retained server-side. Selected Tool route keys equal neutral descriptor names, dropped Tools disappear from both, environment required only for selected environment-dependent Tools and must be compatible. No Tool/environment needed in deterministic example. Actual Agent public display metadata and reset equality cover instance labels/source immutability; core immutable binding contract remains unchanged. Exact4096 metadata bytes accepted and4097 rejected. |
| PA3 | PASS. Strict startup/draft keys, role/node validation, catalogue bounds/references, malformed/improper/duplicate/unknown IDs, invalid UTF-8 and byte limits reject static errors. Model adapter validation reuses ModelBinding/Harness; no browser raw binding/module/node input. Public describe/reset omit binding/base URL/credentials; credential sentinel remains private. Executor settings/roots are not public catalogue fields. Trusted labels/provider content can themselves echo data; no general secret-erasure guarantee. |
| PA4 | PASS after F1. Start and input are separate, one attempt each. Real executable ceiling proves confirmed creation/input rejection retains Ref and navigation. Suspended Agent yields input_unknown; missing trusted remote yields conservative create_unknown with ID. Navigation missing/stalled now cannot erase confirmed Ref or prevent the one input dispatch. Static remote failures are not overclassified as proof of no creation. |
| PA5 | PASS. Random opaque32-byte handle, max4096 retained entries, one-hour idle expiry and periodic cleanup; no transcript or Agent ownership. Fetch performs exact descriptor lookup then exact Ref/incarnation equality. Same-ID replacement stays stale. Independent forged-descriptor and forged-incarnation probes reject without Agent closure. Real Handles death/navigation restart leaves embedded Agent alive; named Web restart clears navigation while remote Agent survives and exact reattachment succeeds. |

Trusted remote name resolution was traced end-to-end: Host validates the complete allowed list through Cluster.connected; Presets.configuration resolves every nonlocal authority through Cluster.authority(target, allowed), validating and atomizing only trusted allowed names. Running catalogue is immutable. Agents.create's String.to_existing_atom therefore consumes a prevalidated existing atom, not a browser-selected arbitrary node name. Browser authority IDs only select catalogue entries; no browser operation calls connect. Direct injection of unvalidated private GenServer startup state is trusted internal misuse, not the browser contract. The named test exercises this actual path.

Handles.remember uses public Agent.lookup's exact three-field descriptor contract, including PID, and fetch additionally compares the complete Ref. Temporary independent probes covered missing/extra descriptor keys, invalid UTF-8 ID, wrong PID, malformed and wrong-size handles, and a changed retained incarnation with unchanged descriptor. Incarnation mismatch rejects; the original Agent remains live. Capacity/expiry tests use controlled state to reach limits and do not claim 4096 distinct real Agents or a one-hour wall-clock soak.

Host rest_for_one order is Node, Presets, Handles, temporary Bootstrap: navigation/catalogue loss cannot restart earlier Node; Node loss clears later navigation; Host/Web loss can lose embedded authority Agents. Endpoint is a separate Application sibling. Existing CSP/controller/nonce regressions still pass. No storage, online preset mutation or new UI route was introduced.

## Executed independent checks

All commands use the installed Elixir1.20.4/OTP29 toolchain; focused gates use ERL_FLAGS='+S 2:2'. Fresh logs have separate exit artifacts.

| Check | Actual result | Artifact |
| --- | --- | --- |
| Pre-fix focused navigation-absence test | Reproduced defect: exit2, 1 failure/10 excluded | navigation-before.log/.exit |
| mix test apps/beamlet_web/test --seed 631927 | exit0, **25 passed / 3 distributed excluded** | web-after.log/.exit |
| Named elixir --sname beamlet_web_independent_review --cookie [private] -S mix test apps/beamlet_web/test --only distributed --seed 631927 | exit0, **3 actual distributed passed / 25 ordinary excluded** | named.log/.exit |
| mix compile --warnings-as-errors | exit0 | compile.log/.exit |
| mix format --check-formatted | exit0 | format.log/.exit |
| mix credo --strict | exit0,126 files/1058 mods-funs, no issues | credo.log/.exit |
| mix dialyzer --no-check | exit0,0 errors/0 skips, existing dev PLT, no refresh | dialyzer.log/.exit |
| mix sobelow | exit0, scan complete, no findings | sobelow.log/.exit |
| MIX_ENV=test mix run -e 'ExUnit.start(seed: 631927); Code.require_file("/tmp/beamlet-web-presets-review/boundaries_test.exs")' | exit0, **3 probes actually passed** | boundaries-executed.log/.exit |
| git diff --check; entry index and original tracked hashes comparison | passed; original index identical and tracked hashes unchanged | tool output; /tmp/web-review-index-before and /tmp/web-review-hashes-before.json |

Named parent uses a newly generated private cookie, passed explicitly rather than inherited setcookie ERL_FLAGS. Test fixtures clean owned peers; successful completion includes teardown. Same-host peers are not physical multi-host or paid-provider proof.

An initial attempt to run the external /tmp probe file with umbrella mix test returned exit0 but **zero tests in every application**; boundaries.log is retained and is explicitly not probe evidence. Corrected invocation loaded and executed all3 probes, recorded separately above. No CLI/provider substitution occurred. Editor LSP reported unavailable/timed-out diagnostics on touched Elixir files; this is inconclusive, not a clean LSP result.

## Existing logs independently inspected; final versus earlier counts

Implementation delivery before this review: Web **23 ordinary passed /3 excluded**, named Web **3 distributed passed /23 excluded**, all delivery static exit artifacts0. This review adds two permanent Web regressions, producing **25 ordinary +3 distributed**. Complete candidate remains15 Web-owned files; review modifies3 of those15. No full umbrella248/other extrapolated count is claimed.

Earlier ordinary candidate: **244 passed /32 distributed excluded**, verified per-app log totals: Harness35, Actions28, Runtime43/6excluded, Agent26, Node68/20excluded, Daemon5/2excluded, CLI18/1excluded, Web21/3excluded. That snapshot preceded the implementation's two final Web additions and this review's two additions. Earlier combined Node+Web named candidate: Node88 and Web22 passed, comprising20+3 actual distributed cases and87 ordinary cases. Its original output is complete but has no separate exit artifact. The subsequent delivery named Web gate and fresh independent named Web gate both have exit0 artifacts. Historical prerequisite230/27 counts are not substituted for this child.

Inspected initial Web fixture cwd failures and erroneous empty-input assumption retained in web-test.log/web-test2.log, and Credo earlier exit4 style findings. Implementation corrected fixture anchoring and used an actual Runtime executable ceiling rather than weakening success requirements. Review failure F1 is separately retained. No historical Runtime composition100ms failure recurred in the focused Web checks/probes; no root-cause conclusion follows.

Inspected backend release build logs/exit0 for both hosts and release-closure.log/exit0. Copied evidence includes manifests, .rel, boot/RPC, invalid-config logs and CLI session artifacts. Copied manifest artifact SHA256 matches the summary: **02ed07f03ecebd3ee8f52e0aff03c0856c22c2a296a33797c40a0a293a94a79f**. Existing gate records copied daemon/CLI closure exclusion of Web/opposite host, same daemon default/authority/executor named start/RPC/pid/stop, bootstrap/Gateway deterministic turn,12 rejected runtime configs, and independent CLI stdin quit/EOF preserving the same Ref then explicit close. Did not gratuitously repeat copied-release/full-umbrella gates for a Handles-only logic repair; backend build excludes Web and no backend source changed.

## Residual risks and next owner obligations

- Historical Runtime composition100ms failure remains **unknown**, previously dispositioned nonblocking. It is not fixed, proved flaky or baseline-proved. On recurrence retain correlated admission/worker/terminal timings and exact outcomes; no timeout increase, weakened success assertion or business retry.
- Local Agent admission can block beyond five seconds and create after caller death; parent was informed. Next LiveView must supply owned caller deadlines, catch availability exits, retain confirmed Ref independently of handle creation, expose uncertainty and use explicit discovery. Helper death is not business rollback or provider cancellation.
- Future LiveView must keep only public descriptors/drafts in browser-facing state, lock duplicate clicks in memory, replace display snapshots including omitted-display clearing, and ack from the subscribed sink. Adapter private resolution results, authority atoms/PIDs/Refs and credential-bearing options stay server-side.
- Named tests are same-host only. Paid providers, physical hosts, browser UX, assets, full check-local, benchmark and SBOM are excluded; no evidence for those is claimed. Existing-PLT analysis did not refresh PLTs. LSP absence remains inconclusive.
- Handles are navigation rather than authorization. Shared exposure needs trusted-network/authenticated-proxy controls and any required per-user core authorization. Web restart does not recover embedded Agents.

No remaining in-scope review blocker. Parent retains shared-spec updates and child/parent final acceptance.
