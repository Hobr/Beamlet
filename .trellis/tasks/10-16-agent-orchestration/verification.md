# CURRENT independent verification — acceptance recommended

Fresh independent exact-source gate passes; no executable files changed in this
recheck. Parent owns acceptance/spec sync/task-state and child4 activation. Review
findings and AC1–AC5/parent disposition are in CURRENT check-report.md; CURRENT
handoff.md is the recommended consumer contract. Older evidence below is historical.

Exact final commands run from repository root:

```bash
ERL_FLAGS='+S 2:2' elixir --sname beamlet_gate_$(date +%s)_$$ --cookie independent_admission_gate --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test apps/beamlet_runtime/test apps/beamlet_agent/test apps/beamlet_node/test --include distributed --seed 631927
ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors
ERL_FLAGS='+S 2:2' mix format --check-formatted
ERL_FLAGS='+S 2:2' mix credo --strict --files-included 'apps/{beamlet_runtime,beamlet_agent,beamlet_node}/**/*.{ex,exs}'
ERL_FLAGS='+S 2:2' mix dialyzer --no-check
(cd apps/beamlet_runtime && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)
(cd apps/beamlet_agent && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)
(cd apps/beamlet_node && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)
git diff --check -- apps/beamlet_runtime apps/beamlet_agent apps/beamlet_node .trellis/tasks/10-16-agent-orchestration
git diff --cached --name-only
```

All gate commands exit0. Tests: Runtime32/Agent4/Node50 = **86 passed**, seed631927,
no exclusions. Named VM explicitly includes Runtime4 + Node2 distributed tests.
Logs `/tmp/child3-gate-tests.log` and `/tmp/child3-gate-{compile,format,credo,dialyzer,deps-runtime,deps-agent,deps-node,whitespace,index}.log`;
serialized command exits also saved in `/tmp/child3-gate-commands.json`.
Credo73 files/575 mods-funs finds no issues. Dialyzer uses existing OTP29.1.2 /
Elixir1.20.4 PLT, no refresh,0 errors/0 skipped/0 unnecessary skips. Runtime
production closure is only Actions; Agent/Node closures are acyclic and have no
Phoenix. No dependency edits. Index output empty.

Non-gate discovery `ls /tmp/*lsp* /tmp/*expert* /tmp/*diagnostic*` had no matching
files (stderr redirected); its standalone status would be2, but the encompassing
shell command ended0 after git status. This is missing diagnostic-artifact evidence,
not a failed validation gate. Broad read-only `rg --files /tmp .trellis` printed
permission-denied entries for other services' private temp directories; piped
listing completed0 and is not a clean exhaustive diagnostic search. Active Expert
process inspection succeeded. No available tool exposes a complete changed-path
LSP sweep, so coverage remains inconclusive. Markdown edit feedback reports clean;
this is not an Elixir diagnostic. No nonzero compile/test/static gate was hidden.

Manual contract checks: public allocation and validation own the complete seam;
OperationOwner imports no coordinator internals. Monitor precedes init limits;
post-read and post-select liveness gates reject observed death without retry.
All four delayed stages assert owner DOWN before resume and no late worker;
selection observes coordinator DOWN. Genuine native progress/terminal retirement,
nested suspended delegation, old-generation fencing/idempotent inventory, peer
full envelopes and ordered whole-batch joins were reviewed and executed after
integration. Source-reviewed quota and fixed timers retain prior independent probe
evidence; this pass did not repeat quota-load or65s elapsed-time probes.

This review changes only:

- .trellis/tasks/10-16-agent-orchestration/check-report.md
- .trellis/tasks/10-16-agent-orchestration/verification.md
- .trellis/tasks/10-16-agent-orchestration/handoff.md
- .trellis/tasks/10-16-agent-orchestration/implement.md

Reviewed repair hashes match the implementation checkpoint exactly. SHA-256 of
repair files plus lifecycle sources/regressions at this independent gate:

```text
f6d61ee8d369929e455cccbb1d4b676aaab6ffe382d9cf49dd51796c47567050  apps/beamlet_runtime/lib/beamlet/runtime.ex
06071d80c1726626a1ef88576dd662ac9a1a7bb925e9fb18c43279a5cdf4fefe  apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex
1755e026b9caa051543ee4215f7c166710c596fa0cbceffc2956e67065d1cd58  apps/beamlet_agent/lib/beamlet/agent/operation_owner.ex
a583fc7ebb55eb2b55536c0648f6704887950031cdb808ab44d5824620a3d95c  apps/beamlet_agent/lib/beamlet/agent/lifecycle.ex
4f211dcda20e5e59bf8e4b125b936f3ab1bc3dc984ac8585eb3b17b4ab6792d8  apps/beamlet_agent/lib/beamlet/agent/resources.ex
ac8d173cd79c0523c11641701d1f9ed709bbd29b8b2a8d0f826f919e5fcf793f  apps/beamlet_agent/lib/beamlet/agent/server.ex
17277489f690564717e9009024130dcf4e7eb25e91197d6abded0020e814c05c  apps/beamlet_agent/lib/beamlet/agent/delegation.ex
d2e3219a530ad7741dad2b67ebfdaf45649a7763fa4e72257a25fb10996f95b3  apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex
cd25284b5d62b0ca1a265dc57f9b30fe4c82e73896d82a967232252365727d76  apps/beamlet_runtime/test/beamlet/runtime_test.exs
774d1aeab0631450e3b40ae9bb33b5685e6e93a93319a7bd7f7d3169e0bb4575  apps/beamlet_runtime/test/beamlet/distributed_test.exs
96a0f231e3d62e105ee6da8cdf72199ddddd63c0d5e7f978c7be427d7709cc05  apps/beamlet_node/test/beamlet/review_test.exs
a8f5b3f6a13eb5dc5840ad52d9663c9d4d518a9ac834fb95092c61841575e15f  apps/beamlet_node/test/beamlet/lifecycle_test.exs
0e136b05b4b6ef2984bb3174b6b2410e14b2c28bec2e29b5676d8fe34896021d  apps/beamlet_node/test/beamlet/distributed_test.exs
67daeb9bdc49b3bbae44c9d85aff24494946e5a297602978453b1b425afccd3d  apps/beamlet_node/test/beamlet/concurrent_tools_test.exs
ead837f573e67b41db052b87219275bc6031168bd556c4d4b3663c3dee941f38  apps/beamlet_node/test/beamlet/node_test.exs
```

Residual limits: liveness checks are not atomic with dispatch; later loss uses
honest existing cleanup. Same-host peers are not physical-host acceptance. No
paid/live provider calls, release boot, hard RSS or hostile-filesystem claims.
No product/test/root/config/dependency/lock/spec/parent/task-state/index/commit
writes; unrelated dirty work and SBOM preserved. Report-only updates after these
passed gates do not require repeating executable checks.

---

# Historical public admission verification — ready for independent recheck only

Child3 acceptance remains pending independent check; child4 must not start.
No unresolved implementation blocker was found in this narrow repair. Current
check-report.md records behavioral coverage and limits; older evidence below is
historical. Final product changes are exactly these six files:

- apps/beamlet_runtime/lib/beamlet/runtime.ex
- apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex
- apps/beamlet_runtime/test/beamlet/runtime_test.exs
- apps/beamlet_runtime/test/beamlet/distributed_test.exs
- apps/beamlet_agent/lib/beamlet/agent/operation_owner.ex
- apps/beamlet_node/test/beamlet/review_test.exs

Only this child's check-report/verification/handoff/implement artifacts are also
updated. Existing dirty work and SBOM commit are preserved; no staging or commits.

Actual commands from repository root (all final commands exit0):

```bash
# Before source edits: public invalid_operation vs private operation_ready.
ERL_FLAGS='+S 2:2' mix run --no-start /tmp/child3-independent-probe.exs
# After: public invalid_operation and operation_failed invalid_operation.
ERL_FLAGS='+S 2:2' mix run --no-start /tmp/child3-independent-probe.exs
# Impacted full suite, 86 passed: Runtime32/Agent4/Node50; seed458366.
ERL_FLAGS='+S 2:2' elixir --sname beamlet_admission_$(date +%s)_$$ --cookie admission_repair --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test apps/beamlet_runtime/test apps/beamlet_agent/test apps/beamlet_node/test --include distributed
# Final affected tests after alias/docs/remote-owner assertions; 47 passed,
# Runtime19/Node28, seed750289. No further executable edits followed.
ERL_FLAGS='+S 2:2' elixir --sname beamlet_admission_final_$(date +%s)_$$ --cookie admission_repair --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test apps/beamlet_runtime/test/beamlet/runtime_test.exs apps/beamlet_runtime/test/beamlet/distributed_test.exs apps/beamlet_node/test/beamlet/review_test.exs --include distributed
ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors
ERL_FLAGS='+S 2:2' mix format --check-formatted
ERL_FLAGS='+S 2:2' mix credo --strict --files-included 'apps/{beamlet_runtime,beamlet_agent,beamlet_node}/**/*.{ex,exs}'
ERL_FLAGS='+S 2:2' mix dialyzer --no-check
(cd apps/beamlet_runtime && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)
(cd apps/beamlet_agent && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)
(cd apps/beamlet_node && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)
git diff --check -- apps/beamlet_runtime apps/beamlet_agent apps/beamlet_node .trellis/tasks/10-16-agent-orchestration
git diff --cached --name-only
```

Logs: `/tmp/admission-before.log`, `/tmp/admission-after.log`,
`/tmp/admission-named.log`, `/tmp/admission-final-focused.log`, and
`/tmp/admission-final-{compile,format,credo,dialyzer,deps-runtime,deps-agent,deps-node,whitespace,index}.log`.
Final strict Credo73 files/575 mods/funs has no issues; Dialyzer existing PLT
0 errors/0 skipped/0 unnecessary skips. Runtime production closure remains only
Actions; no dependencies were changed. Index empty. No PLT refresh/suppressions.
Full run included both real distributed suites (Runtime4 and Node2 cases); final
affected run repeats Runtime distributed tests. Same-host peers are not physical
multi-host acceptance.

Intermediate focused command `ERL_FLAGS='+S 2:2' mix test apps/beamlet_runtime/test/beamlet/runtime_test.exs apps/beamlet_node/test/beamlet/review_test.exs`
passed46, seed521227, but emitted warnings from constant generated stage branches
(`/tmp/admission-focused.log`). A single runtime stage loop removes those warnings.
Initial `/tmp/admission-credo.log` reported two test alias suggestions, now fixed.
Final checks above supersede these intermediates. There were no final test failures.

Manual review: monitor is installed before init Directory read; liveness is checked
after limits and after selection as well as before dispatch. Delayed tests assert
owner DOWN before resume for all four stages; no execution afterward and no
coordinator retention for rejected startup. Remote-owner default compatibility,
guarded restriction, ignored-start normalization and public/consumer error parity
have behavioral evidence. Prior fixed deadlines, Resources duplicate accounting,
terminal retirement, progress identity and quota code remain untouched.

LSP pending/absence/timeouts are inconclusive. No paid/live provider, physical-host
or release tests were performed. Parent owns acceptance and spec/task bookkeeping.

Final SHA-256 inventory:

```text
f6d61ee8d369929e455cccbb1d4b676aaab6ffe382d9cf49dd51796c47567050  apps/beamlet_runtime/lib/beamlet/runtime.ex
06071d80c1726626a1ef88576dd662ac9a1a7bb925e9fb18c43279a5cdf4fefe  apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex
1755e026b9caa051543ee4215f7c166710c596fa0cbceffc2956e67065d1cd58  apps/beamlet_agent/lib/beamlet/agent/operation_owner.ex
cd25284b5d62b0ca1a265dc57f9b30fe4c82e73896d82a967232252365727d76  apps/beamlet_runtime/test/beamlet/runtime_test.exs
774d1aeab0631450e3b40ae9bb33b5685e6e93a93319a7bd7f7d3169e0bb4575  apps/beamlet_runtime/test/beamlet/distributed_test.exs
96a0f231e3d62e105ee6da8cdf72199ddddd63c0d5e7f978c7be427d7709cc05  apps/beamlet_node/test/beamlet/review_test.exs
```

---

# Historical independent final-source verification — acceptance BLOCKED

Final independent named run: **53 passed, Agent4 + Node49, seed408204**; both
actual distributed tests executed, no exclusions. Initial unchanged recheck:
52 passed, seed395250. Source repair adds one regression and PID idempotency;
no executable changes followed the final run. check-report.md records the sole
remaining Runtime public-submit boundary blocker and acceptance matrix.

Exact commands from repository root:

```bash
ERL_FLAGS='+S 2:2' elixir --sname beamlet_independent_final_$(date +%s)_$$ --cookie independent_lifecycle_final --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test apps/beamlet_agent/test apps/beamlet_node/test --include distributed
ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors
ERL_FLAGS='+S 2:2' mix format --check-formatted
ERL_FLAGS='+S 2:2' mix credo --strict --files-included 'apps/beamlet_agent/**/*.{ex,exs}' --files-included 'apps/beamlet_node/**/*.{ex,exs}'
ERL_FLAGS='+S 2:2' mix dialyzer --no-check
(cd apps/beamlet_node && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)
git diff --check -- apps/beamlet_agent apps/beamlet_node .trellis/tasks/10-16-agent-orchestration
git diff --cached --name-only
```

Logs `/tmp/child3-independent-final-{tests,compile,format,credo,dialyzer,deps,whitespace,index}.log`.
Compile/format/deps/whitespace/index commands explicitly repeated through a
subprocess runner: each exit0, index empty. Credo passes73 printed files /562
mods/funs with explicit scoped globs. Existing-PLT Dialyzer passes0 errors,
0 skipped,0 unnecessary skips, no PLT refresh. Parallel Mix checks briefly waited
for shared build locks; final serialized compile/format succeeded. No suppressions.

Focused regression commands:

```bash
ERL_FLAGS='+S 2:2' mix test apps/beamlet_node/test/beamlet/review_test.exs:112
ERL_FLAGS='+S 2:2' mix run --no-start /tmp/child3-independent-probe.exs
ERL_FLAGS='+S 2:2' mix run --no-start /tmp/child3-independent-quota.exs
```

Duplicate-registration test: before0/1 passed,26 excluded, expected assertion
3 slots !=1; after1 passed,26 excluded. Logs
`/tmp/child3-independent-duplicate-{before,after}.log`. After correcting the test
worker to link its controller as actual lifecycle workers do, retirement is also
asserted after both DOWN. The before assertion fails before that cleanup branch.

Manual parity probe: Runtime rejects budget_ms:0, private adapter returns ready
ref. Inventory before fix:102 entries for2 unique PIDs. Quota probe:1024 of each
kind admitted;1025th killed and observed DOWN. Fixed admission timer:5003ms DOWN
while Coordinators suspended; resume leaves0 coordinators. Scripts and logs in
/tmp, durable steps/results in current check-report. These are infrastructure
probes, not paid/native-provider/physical/release acceptance. Fixed total65s timer
source-reviewed; arbitrary hostile forged resource messages not claimed bounded.

Active Expert project processes found; no callable complete diagnostic sweep.
LSP inconclusive. Intentional lifecycle faults log killed infrastructure and safe
late-helper dead-link rejection. No stage/commit/upstream/root/config/lock/spec/
parent/task-state writes. Durable CURRENT handoff remains blocked.

Exact executable SHA-256 inventory (Agent/Node source/manifests/tests):

```text
a46ecd2cb12fd54c0cf0928c72fb10bef329b3f72b49df9bef621c3370734bc5  apps/beamlet_agent/.formatter.exs
d2e3219a530ad7741dad2b67ebfdaf45649a7763fa4e72257a25fb10996f95b3  apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex
17277489f690564717e9009024130dcf4e7eb25e91197d6abded0020e814c05c  apps/beamlet_agent/lib/beamlet/agent/delegation.ex
255b14f1cc06907d1d61d9e458429b5aff3dbfa56f61f0b06c8b7754bd923df4  apps/beamlet_agent/lib/beamlet/agent/integration/caller.ex
3771793968dc895e25997a0660ecbc98ff5643a70f367662cc1f1badbfbf2dad  apps/beamlet_agent/lib/beamlet/agent/integration/handler.ex
a583fc7ebb55eb2b55536c0648f6704887950031cdb808ab44d5824620a3d95c  apps/beamlet_agent/lib/beamlet/agent/lifecycle.ex
6856bcbde3e60bdada43afa9c4b423372a97b75507f9a78dbef3fb172bf87b6d  apps/beamlet_agent/lib/beamlet/agent/operation_owner.ex
658448d2c47b66230077fc6c1991e50f728f077c95fd4e61be15bc4605519fb1  apps/beamlet_agent/lib/beamlet/agent/ref.ex
4f211dcda20e5e59bf8e4b125b936f3ab1bc3dc984ac8585eb3b17b4ab6792d8  apps/beamlet_agent/lib/beamlet/agent/resources.ex
ac8d173cd79c0523c11641701d1f9ed709bbd29b8b2a8d0f826f919e5fcf793f  apps/beamlet_agent/lib/beamlet/agent/server.ex
e008c941f84f645962aa07aa7f410d5146183aca43efc9420cb6b70802386aaf  apps/beamlet_agent/lib/beamlet/agent.ex
850d7df280f31756bf2beb9015ec0b497a84b23a50bbad941a3da1cdb135515e  apps/beamlet_agent/mix.exs
fcf59f2712e7dff9a4298048156e4d8140adf3c8d59c52fd14f04e34985f2505  apps/beamlet_agent/test/beamlet/agent_test.exs
b086ec47f0c6c7aaeb4cffca5ae5243dd05e0dc96ab761ced93325d5315f4b12  apps/beamlet_agent/test/test_helper.exs
a46ecd2cb12fd54c0cf0928c72fb10bef329b3f72b49df9bef621c3370734bc5  apps/beamlet_node/.formatter.exs
ae3b8bacc8cd4a1c8ba38b70e65ae93e42989afb7fa380f2d9c3769779f17e56  apps/beamlet_node/lib/beamlet/node/application.ex
1dcc9a1c74741d3c2da927ccbc999b24177fb364f1ccf2918a4aae2bf5b588d2  apps/beamlet_node/lib/beamlet/node/provider.ex
1bf20c0f2dc74a5316d81bbba5119a724584663929c114abf95691c83a2a8a00  apps/beamlet_node/lib/beamlet/node/routes.ex
0c2115e797d6566bdbefc99aa4702ad0d94884b78a4d0b3ab5998c0d7be5fa79  apps/beamlet_node/lib/beamlet/node/runtime.ex
bad83de717c8863c96b50ef9decda3371f8559383f4338e7cafeb6678a9b9aa0  apps/beamlet_node/lib/beamlet/node.ex
5275a2fe2a2098efc2394f220071b137e70d105d004f1e3229aabf1d71ab77fe  apps/beamlet_node/mix.exs
67daeb9bdc49b3bbae44c9d85aff24494946e5a297602978453b1b425afccd3d  apps/beamlet_node/test/beamlet/concurrent_tools_test.exs
0e136b05b4b6ef2984bb3174b6b2410e14b2c28bec2e29b5676d8fe34896021d  apps/beamlet_node/test/beamlet/distributed_test.exs
a8f5b3f6a13eb5dc5840ad52d9663c9d4d518a9ac834fb95092c61841575e15f  apps/beamlet_node/test/beamlet/lifecycle_test.exs
ead837f573e67b41db052b87219275bc6031168bd556c4d4b3663c3dee941f38  apps/beamlet_node/test/beamlet/node_test.exs
f5a3d19af95285408f90b4c71605a9694de026d9fbf6f748be3753cde180a5f7  apps/beamlet_node/test/beamlet/review_test.exs
b2c2242de0de7b03349922f4f4c895a4cbe606943c3d542bb86baa26b7329e4b  apps/beamlet_node/test/support/fixtures.ex
d561676aaaa1855a8933f955a3a0231c910edae34e00e8b9051e313393940370  apps/beamlet_node/test/support/loop_model.ex
f10244f54c202fb8dbc2d0e13cb4921c34eb784c7f40d394a0cc02ff526a44ac  apps/beamlet_node/test/test_helper.exs
```

---

# Historical verification — superseded by CURRENT evidence above

# Lifecycle repair final-source verification

Final executable source and tests: 52 passed, Agent4 + Node48, seed318484, two
actual distributed tests executed, no exclusions. Evidence logs:
`/tmp/child3-lifecycle-deliver-{named,compile,format,credo,dialyzer}.log`.

Exact final-source commands from repository root:

```bash
ERL_FLAGS='+S 2:2' elixir --sname beamlet_lifecycle_deliver_$(date +%s)_$$ --cookie child3_lifecycle_deliver --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test apps/beamlet_agent/test apps/beamlet_node/test --include distributed
ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors
ERL_FLAGS='+S 2:2' mix format --check-formatted
ERL_FLAGS='+S 2:2' mix credo --strict --files-included 'apps/beamlet_agent/**/*.{ex,exs}' --files-included 'apps/beamlet_node/**/*.{ex,exs}'
ERL_FLAGS='+S 2:2' mix dialyzer --no-check
(cd apps/beamlet_node && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)
git diff --check -- apps/beamlet_agent apps/beamlet_node .trellis/tasks/10-16-agent-orchestration
git diff --cached --name-only
```

Compile/format passed. Credo explicitly scoped to Agent/Node passed, printed73
files/562 modules/functions. Dialyzer existing PLT passed with0 errors/0 skips/0
unnecessary skips; no refresh. Dependency tree passed earlier with unchanged
manifests and is repeated at artifact closure. Whitespace/index checks repeated
at closure. No index writes, commits, task-state, upstream/config/lock/spec/parent
writes. Diagnostic feedback was sometimes clean/pending/unavailable; complete
standalone LSP remains inconclusive. Existing disk alarm and intentional fault
logs remain; late helper :noproc link logs are safe dead-owner rejection, not
business execution or suppressed failures.

## Behavioral comparison and intermediate failures

`/tmp/child3-baseline-compare.py` temporarily restored the old raw operation-owner
submit/ack loop, raw delegation admission and early terminal-owner removal (arity
adapters retained for current callers), then restored final files in finally.
This is an explicitly reconstructed pre-repair behavior comparison, not a claim
that the entire earlier checkout was restored. Existing independent exact-source
probes remain documented below. Comparison command selected the then-current
review tests at lines112/150/226; `/tmp/child3-lifecycle-before-comparison.log`,
seed267414, exit2, **0/3 passed**, intended assertions actually executed:
operation-admission DOWN absent at3000ms while Coordinators suspended; parent/local
Agent-admission DOWN absent while Agents suspended; genuine progress/Runtime
terminal leaves live owner outside accounting during blocked ack. Temporary
comparison warnings were unused final helper/alias due to the old logic; these
were not setup/tool failures and are absent from final source.

Intermediate real-source checks: initial focused suite4 failures (concurrent
Tool join, expiry forwarding, and two old tests assuming resumed cleanup); healthy
join now requires all original ordered results, expiry forwards to helper, and
cleanup tests assert DOWN before resume. New nested test initially stopped its
child before freezing the observing helper, which correctly closed the child;
fixture now freezes that helper before exercising nested shutdown. Initial Credo
reported two aliases and nested callback complexity; extracted helper/aliases
without suppressions. Restart test initially queried supervisor readiness before
old-Agent DOWN (intermittent authority_unavailable); readiness barrier corrected.
Later named run seed739757 exposed an existing test assumption that native worker
start implies pending registration; added bounded TestBoot.pending barrier rather
than changing asynchronous product semantics. Those failed runs are historical,
not final acceptance. Final named run supersedes them.

## Exact final executable-source SHA-256 inventory

```text
d2e3219a530ad7741dad2b67ebfdaf45649a7763fa4e72257a25fb10996f95b3  apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex
6856bcbde3e60bdada43afa9c4b423372a97b75507f9a78dbef3fb172bf87b6d  apps/beamlet_agent/lib/beamlet/agent/operation_owner.ex
17277489f690564717e9009024130dcf4e7eb25e91197d6abded0020e814c05c  apps/beamlet_agent/lib/beamlet/agent/delegation.ex
ac8d173cd79c0523c11641701d1f9ed709bbd29b8b2a8d0f826f919e5fcf793f  apps/beamlet_agent/lib/beamlet/agent/server.ex
a583fc7ebb55eb2b55536c0648f6704887950031cdb808ab44d5824620a3d95c  apps/beamlet_agent/lib/beamlet/agent/lifecycle.ex
d3abd01cbf59580e0ddb559c49e7e919aef634dcb4ffc4aa42af3d22d921d925  apps/beamlet_agent/lib/beamlet/agent/resources.ex
5729143187356e62b40ab8ad683c7e402b7c6b8c6058d54fe711b3ff033d7854  apps/beamlet_node/test/beamlet/review_test.exs
a8f5b3f6a13eb5dc5840ad52d9663c9d4d518a9ac834fb95092c61841575e15f  apps/beamlet_node/test/beamlet/lifecycle_test.exs
b2c2242de0de7b03349922f4f4c895a4cbe606943c3d542bb86baa26b7329e4b  apps/beamlet_node/test/support/fixtures.ex
```

No executable source changes followed this inventory. Reports/plan changes do
not alter the tested source. Root-cause retrospective and ownership/count details
are in the current check-report. Ready only for independent recheck; child4 stays
blocked. No physical-host, paid/live, release, hard RSS or external rollback claim.

---

# Historical verification (superseded for current source)

# Independent final recheck verification — acceptance blocked

Final impacted commands from repository root:

```bash
ERL_FLAGS='+S 2:2' elixir --sname beamlet_recheck_gate_$(date +%s)_$$ --cookie child3_independent_gate --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test apps/beamlet_agent/test apps/beamlet_node/test --include distributed
ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors
ERL_FLAGS='+S 2:2' mix format --check-formatted
ERL_FLAGS='+S 2:2' mix credo --strict --files-included 'apps/beamlet_agent/**/*.{ex,exs}' --files-included 'apps/beamlet_node/**/*.{ex,exs}'
ERL_FLAGS='+S 2:2' mix dialyzer --no-check
(cd apps/beamlet_node && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)
git diff --check -- apps/beamlet_agent apps/beamlet_node .trellis/tasks/10-16-agent-orchestration
git diff --cached --name-only
rg -n 'Beamlet\.(Harness|Agent)|beamlet_(harness|agent)' apps/beamlet_runtime/lib apps/beamlet_runtime/mix.exs
```

- `/tmp/child3-recheck-gate.log`: exit 0, seed **55799**, **Agent 4 + Node 40 =
  44 passed**, both actual distributed tests executed, no exclusions. Named
  same-host peers only; unique VM name, isolated cookie, two schedulers, bounded
  peer boot/teardown and explicit discovery/stdio partition controls preserved.
- `/tmp/child3-recheck-final-compile.log`: exit 0, no warnings. Final executable
  source was compiled; subsequent edits only introduce aliases in tests.
- `/tmp/child3-recheck-final-format.log`: exit 0; formatter check also reran after
  test aliases, exit 0.
- `/tmp/child3-recheck-final-credo.log`: final exit 0, no issues, printed 71 files /
  529 modules/functions with explicit Agent/Node globs. Earlier this recheck found
  two alias suggestions in the new test; fixed without suppression, then reran.
- `/tmp/child3-recheck-final-dialyzer.log`: exit 0, **0 errors, 0 skipped, 0
  unnecessary skips**, existing PLT, no refresh. Informational absent ignore file
  notice remains visible.
- `/tmp/child3-recheck-deps.log`: exit 0; Node prod closure contains only the four
  core apps and Harness HTTP/JSON/OTP dependencies; no Web/Phoenix application or
  sibling dependency cycle. Runtime dependency grep has no matches (expected
  exit 1). Scope whitespace exit 0; index inventory empty, no index mutation.

Two added affirmative regressions: owner loss before readiness yields explicit
infrastructure_lost; present/unavailable Directory never widens executable cap.
The owner-loss regression was first run at line 216 accidentally selecting the
preceding existing test (passed); corrected line 217 failed before source fix in
`/tmp/child3-final-regression-before.log`, then passed after repair in
`/tmp/child3-final-regression-after.log`. Final suite includes both new tests (18
review tests). Earlier final-source intermediate runs: 43 passed seed129460 before
cap repair; 44 passed seed301024 before test-only alias cleanup. Final gate above
supersedes these. No unchanged broad umbrella upstream rerun was necessary.

## Independent behavioral defect probes (not passing acceptance evidence)

1. `ERL_FLAGS='+S 2:2' mix run --no-start /tmp/child3-final-probe.exs`, final exit 0,
   `/tmp/child3-final-probe.log`: start authority-only Node; start Agent; suspend
   Coordinators; input and snapshot barrier; record owner PID/stack; close Agent;
   terminate authority subtree with Supervisor.terminate_child; wait5200ms. Owner
   still alive in Runtime.submit/gen.do_call. Resume Coordinators: owner exits.
   Restart authority; suspend Delegations; delegate and snapshot barrier; record
   launcher PID; close parent; wait5200ms: launcher alive in Task.Supervisor
   admission/gen.do_call. Resume Delegations: launcher exits. These observations
   plus infinity-call source establish missing admission lifetime bounds, without
   inferring infinite elapsed execution from a finite test.
2. `MIX_ENV=test ERL_FLAGS='+S 2:2' mix run --no-start /tmp/child3-final-real-ack.exs`,
   final exit 0, `/tmp/child3-final-real-ack.log`: configured native provider waits
   release, calls native Context.progress and returns a canonical text reply.
   After input/start observation, suspend Agent; release provider; poll Agent
   mailbox for actual Runtime terminal (bounded100x10ms). Both actual progress
   and Result are queued. Suspend coordinator; resume Agent; snapshot is done.
   After30ms, owners map size is0 while owner is alive in Runtime.ack/gen.do_call;
   another input returns ok. Resume coordinator/close Agent. No synthetic Result,
   state replacement, retry or provider-side message fabrication is used. A prior
   synthetic-terminal probe also showed the issue but is not the decisive evidence.

The probes were rerun after final source repairs and still reproduce. Their full
scripts/logs are in /tmp; durable reproduction steps and observed values above
remain the evidence if temporary artifacts expire. No source acceptance test was
made to pass by asserting these defects exist.

Diagnostics: available edit feedback reports pending lsp on Server/Caller; no
callable standalone active changed-file diagnostics/query tool exists here.
Coverage remains **inconclusive**. Compile/static tests are not substituted for an
LSP sweep. Intentional Registry/gateway fault logs and existing disk alarm remain.
No release assembly, physical hosts, paid model, external rollback or hard RSS
claim. Check-report.md owns the blocked acceptance disposition.

---

# Historical verification — superseded by independent final evidence above

# Final remediation verification

Final-source commands from repository root (logs in `/tmp`, no live provider or
physical-host claims):

```bash
ERL_FLAGS='+S 2:2' elixir --sname beamlet_remediation_$(date +%s)_$$ --cookie remediation_5931 --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test apps/beamlet_agent/test apps/beamlet_node/test --include distributed
ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors
ERL_FLAGS='+S 2:2' mix format --check-formatted
ERL_FLAGS='+S 2:2' mix credo --strict --files-included 'apps/beamlet_agent/**/*.{ex,exs}' --files-included 'apps/beamlet_node/**/*.{ex,exs}'
ERL_FLAGS='+S 2:2' mix dialyzer --no-check
git diff --check -- apps/beamlet_agent apps/beamlet_node .trellis/tasks/10-16-agent-orchestration
git diff --cached --name-only
```

- `/tmp/child3-remediation-named.log`: **Agent 4 + Node 38 = 42 passed**, seed
  **501169**, two actual three-peer distributed tests executed, no exclusions.
  Review suite now has **16 tests**, replacing the known_blocker stall assertion
  with affirmative responsiveness. Added stop/loss during delayed submission and
  child creation, coordinator/helper-supervisor suspension, partial admission
  saturation, attempt/sequence/turn/ref correlation and exact full-envelope edges.
- `/tmp/child3-remediation-compile.log` and `...-format.log`: exit 0, no output.
- `/tmp/child3-remediation-credo.log`: exit 0, explicit Agent/Node globs, printed
  71 files / 529 modules/functions, no issues. No suppression/exclusion added.
- `/tmp/child3-remediation-dialyzer.log`: exit 0, **0 errors, 0 skipped,
  0 unnecessary skips**, existing PLT; no refresh attested.
- Whitespace passed; index inventory empty. No index writes, commits or upstream,
  root config/lock, spec, parent or task-state edits by this worker.

Intermediate failures were repaired, not counted as final acceptance: historical
stall assertion initially failed because input had become responsive; first named
run failed four standalone-authority tests due to absent Directory and one helper
expiry test due to launcher forwarding. Preserved protocol fallback for absent
Runtime and forwarded helper observation signals. A later named run exposed a
completed-owner/next-input race; validated terminal acceptance now retires finished
owners before publication. Last test-edit run had one assertion expecting a newer
progress value without sending that event; corrected the fixture and reran all
impacted checks. Credo initially found alias order/nested callback complexity;
extracted local helpers without suppressions. Final evidence above supersedes
those failed runs. Prior logs may have been overwritten by final-source runs.

Diagnostics: edit-backed Elixir feedback was clean on initial OperationOwner write;
compile warnings-as-errors and Dialyzer cover final source. No complete standalone
LSP sweep is claimed. Intentional fault crash logs and existing disk alarm remain
visible. Same-host peer tests exercise distribution, never physical-host acceptance.
Cancellation/owner DOWN does not establish remote service rollback or billing.
Independent recheck and parent final bookkeeping remain external gates.

---

## Historical evidence before remediation (not current acceptance)

# Child 3 verification checkpoint

Recovered after the original worker's runtime limit. Implementation remains scoped to Agent/Node; independent trellis-check is pending. This document records saved evidence rather than inferring success from task state.

## Saved executable evidence

Logs recovered from `/tmp/child3-*.log` on the same checkout:

- `ERL_FLAGS='+S 2:2' mix test apps/beamlet_agent/test apps/beamlet_node/test`: `/tmp/child3-focused.log` reports Agent **4 passed**, Node **19 passed, 2 distributed excluded**.
- `ERL_FLAGS='+S 2:2' elixir --sname beamlet_child3_acceptance --cookie child3_acceptance_5931 --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test --include distributed`: `/tmp/child3-final-tests.log` reports Harness **26**, Actions **5**, Runtime **28**, Agent **4**, Node **21**, Web **7**, all passed: **91 executed**, including Runtime **4** and Node **2** distributed-tag tests. No exclusions reported in this run.
- `ERL_FLAGS='+S 2:2' mix dialyzer --no-check`: `/tmp/child3-dialyzer.log` reports **0 errors, 0 skipped, 0 unnecessary skips**, passed. This analyzes against the existing dependency PLT; it does not attest a refreshed PLT. The missing ignore_warnings option notice is informational; no suppression was added.
- `ERL_FLAGS='+S 2:2' mix credo --strict --files-included 'apps/beamlet_agent/**/*.{ex,exs}' --files-included 'apps/beamlet_node/**/*.{ex,exs}'`: `/tmp/child3-credo-scoped.log` reports **69 files, 498 modules/functions, no issues**. Scope was confirmed during closure using `mix credo info` with the same include switches: `/tmp/child3-credo-info.json` enumerates exactly **23** Agent/Node source, manifest, helper and test files (the two formatter configuration files are excluded). Credo's suggest summary still prints 69; the explicit info inventory establishes the requested scope.
- `/tmp/child3-xref.log`: xref graph stats report 43 tracked files and 3 cycles. Earlier command output identifies ordinary runtime cycles Agent→Server→Delegation→Agent and Directory↔Gateway, plus the existing Web compile cycle. Compile-connected cycles output identified only Web. No application dependency cycle was introduced.
- `(cd apps/beamlet_node && ERL_FLAGS='+S 2:2' mix deps.tree --only prod)`: `/tmp/child3-deps.log` shows only Actions/Agent/Runtime/Harness plus Harness's HTTP/JSON dependencies, with no Web/Phoenix dependency.

Original conversation tool output records successful `mix compile --warnings-as-errors`, umbrella `mix format --check-formatted`, and scoped `git diff --check`; their output was not saved in separate logs. These short gates will be checkpointed again during bounded closure. Original failed attempts (subsequently repaired) included ungrouped ready?/1 and control/2 clauses, an unavailable Directory race in a fault-test readiness barrier, and early Credo findings. None were suppressed.

## Coverage and boundaries

Agent tests cover 128-Agent admission, identity uniqueness/stale refs, snapshot-first order, subscriber count and oversize input. Node tests cover actual three named same-host role VMs, remote model/workspace eligibility with no fallback, reversed parallel Tool completions and multiple Agents, malformed native sibling batch with zero dispatch, delegation joining/continuation/stop/delegator loss/stale group/disconnect, independent peers/expiry/loss/stale receiver turn, slow-client credits, context growth through 64 actual turns to 128 messages, 16 model steps, peer/delegation/message limits, smaller Runtime executable ceilings, coordinator loss without terminal notification, and active provider/gateway/Registry fault cleanup.

Early partition automation emitted OTP global overlapping-partition notices, which can cause collateral disconnects. Later peers and the controller explicitly use `-kernel prevent_overlapping_partitions false`; the final saved 91-test run contains no overlapping-partition notices. Stdio peer control remains available while distribution is disconnected. This is an automation-only topology setting, not product deployment guidance. Fault tests intentionally log killed Registry/Endpoint processes; worker DOWN proves local BEAM termination, not remote provider rollback.

## Bounded recovery closure

The recovered source already groups all three `ready?/1` clauses together (provider.ex lines 14, 20, 36); no warning suppression was added. Direct recovery runs of `mix compile --warnings-as-errors`, umbrella `mix format --check-formatted`, and scoped `git diff --check` passed.

Final API/source alignment found and repaired one concrete delegation boundary: a scheduled `:expired` message was not handled, leaving a resettable receive timeout, and error/stop snapshots cleared active turn identity. The helper now handles the fixed timer message; snapshots retain `terminal_turn`, and child error/stop observations must match that exact turn. The new regression injects a stale child terminal snapshot followed by the expiry signal, asserts expiry rather than stale success/error, observes worker DOWN, and separately joins a genuine no-target child failure with its turn preserved.

After these scoped changes, the impacted checks ran once:

- `ERL_FLAGS='+S 2:2' elixir --sname beamlet_child3_closure --cookie child3_closure_6618 --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test apps/beamlet_agent/test apps/beamlet_node/test --include distributed`: `/tmp/child3-closure-tests.log`, **Agent 4 passed; Node 22 passed (20 local + 2 distributed); 26 executed total**, no exclusions or overlapping-partition notices. This is the final-source test run. The earlier 91-test umbrella record predates this narrow closure repair; unchanged upstream tests were not broadly rerun.
- `mix compile --warnings-as-errors` and umbrella `mix format --check-formatted`: direct tool exit success, no output/warnings.
- Strict Credo with the same two include globs: `/tmp/child3-closure-credo.log`, no issues (printed summary 69 files / 498 modules/functions; explicit scoped inventory 23 files as above).
- `mix dialyzer --no-check`: `/tmp/child3-closure-dialyzer.log`, **0 errors/skips/unnecessary skips**, passed against the existing PLT.

## Remaining gates

Independent parent trellis-check, spec updates, commit/archive bookkeeping and child-4 release/physical-host acceptance remain outside this worker's write scope. No planned child-3 feature was intentionally deferred. Full standalone changed-file LSP coverage remains unverified: edit-backed feedback included clean results and some pending runner indications, which are not counted as a clean workspace sweep.

No live paid provider, physical multi-host deployment, hostile filesystem confinement, durable delivery/replay, or reliable remote cancellation is attested. Edit-backed Elixir diagnostics reported clean on edited files after repairs; no complete standalone changed-file LSP sweep was exposed, so full LSP coverage is not claimed. Whole-envelope retention bounds are not hard RSS limits. Existing upstream dirty files and locks are preserved.


## Independent review validation (supersedes pending-review status above)

Acceptance remains **blocked**; see check-report.md. This worker changed only
Agent/Node and this child's authorized reports/plan. Eight regression tests were
added in `apps/beamlet_node/test/beamlet/review_test.exs`: canonical native mismatch,
helper crash/child and worker termination, malformed delegation rejection, exact
executor requests, native callback registration, safe non-JSON Tool data failure,
malformed terminal rejection, and a known-blocker Directory suspension repro.
The latter deliberately passes when callback blocking is observed; it is evidence
of a remaining defect, never evidence of acceptable responsiveness.

Commands run from repository root, outputs preserved in `/tmp/child3-review-*.log`:

- `ERL_FLAGS='+S 2:2' mix test apps/beamlet_node/test/beamlet/review_test.exs`:
  `/tmp/child3-review-focused.log`, **8 passed**. Earlier first revision: 6 passed.
- `ERL_FLAGS='+S 2:2' elixir --sname beamlet_review_final_$(date +%s)_$$ --cookie child3_review_final_$(date +%s)_$$ --erl '+S 2:2 -kernel prevent_overlapping_partitions false' -S mix test apps/beamlet_agent/test apps/beamlet_node/test --include distributed`:
  `/tmp/child3-review-final-tests.log`, seed **568501**, **Agent 4 + Node 30 = 34
  passed**, two distributed tests actually executed, no exclusions. Earlier review
  revision: 32 passed (Agent 4 + Node 28). Last edits after the final run only
  sort/shorten test aliases for Credo; executable source is identical.
- `ERL_FLAGS='+S 2:2' mix compile --warnings-as-errors`:
  `/tmp/child3-review-compile.log`, exit 0, no warnings/output.
- `ERL_FLAGS='+S 2:2' mix format --check-formatted`:
  `/tmp/child3-review-format.log`, exit 0. Focused mix format used only authorized
  edited Elixir files. Final alias reordering does not alter formatter layout.
- `ERL_FLAGS='+S 2:2' mix credo --strict --files-included 'apps/beamlet_agent/**/*.{ex,exs}' --files-included 'apps/beamlet_node/**/*.{ex,exs}'`:
  `/tmp/child3-review-credo.log`, **no issues**, printed 70 files / 512 modules and
  functions. Earlier attempts failed on handler nesting/alias and test aliases;
  repaired without exclusions or suppressions. Include globs supplied explicitly;
  no independent `credo info` scope inventory was repeated this session.
- `ERL_FLAGS='+S 2:2' mix dialyzer --no-check`:
  `/tmp/child3-review-dialyzer.log`, **0 errors, 0 skipped, 0 unnecessary skips**,
  existing dependency PLT, no refresh claimed.
- `git diff --check -- apps/beamlet_agent apps/beamlet_node .trellis/tasks/10-16-agent-orchestration`:
  exit 0; `git diff --cached --name-only`: empty index. No index-writing commands.
- `rg -n 'Beamlet\.(Harness|Agent)|beamlet_(harness|agent)' apps/beamlet_runtime/lib apps/beamlet_runtime/mix.exs`:
  no matches (expected rg exit 1); no Runtime-to-Harness/Agent import found.
- Manual full-peer-envelope probe via `ERL_FLAGS='+S 2:2' mix run --no-start -e`
  constructed valid Ref IDs of 128 bytes and an 8100-byte payload, applied the
  same Operation validation, then external_size to payload and full peer_request:
  `/tmp/child3-review-envelope.log`, **8106 vs 8767 bytes**. This proves the remaining
  full-message 8192-byte cap defect; it does not claim API acceptance is repaired.

Peer startup uses unique names/cookie, two schedulers, 10-second boot, 3-second
shutdown, stdio control and explicit discovery barriers. Tests assert three role
VM placement, worker DOWN, correlated child loss and no observed recreation;
no overlapping-partition global warnings occurred. Controller/peer test-only
partition setting is unchanged; no deployment recommendation is inferred.
Intentional Registry/gateway fault logs and host disk alarm remain visible.
No unchanged umbrella/full upstream tests were rerun; prior 91-test evidence is
historical as explained above. No paid calls or physical-host claims. LSP feedback
was partial/asynchronous and is not counted as a clean complete sweep.
