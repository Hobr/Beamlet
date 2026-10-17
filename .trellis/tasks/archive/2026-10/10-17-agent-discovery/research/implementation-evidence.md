# Discovery implementation evidence

Candidate implemented in `/mnt/data/Project/Beamlet`, dev baseline0fed1b1 plus
accepted prerequisite work. Single writer, no recursive workers or independent
review claimed. Public CLI contract is recorded in ../implement.md; transport and
startup amendment was persisted in ../design.md before product writes.

## Ownership / source proof

- Agent facade delegates list/lookup to Agent.Discovery; Registry identity-only
  selection, no per-Server list calls. Lookup reuses existing Server `:ref` handler
  and verifies actual Ref authority/ID/PID/reference incarnation. Never constructs
  Ref or accesses private Server state. Server source is unchanged.
- Agent-owned Discovery.Endpoint is started last by standalone AuthoritySupervisor
  (authority=true) in its existing one_for_all island. All non-authority Node role
  subsets supervise the same fixed-name endpoint with authority=false; authority
  subsets use only the AuthoritySupervisor child. All seven role regressions pass.
  Dependency loading remains side-effect free. No Agent->Node/host dependency.
- Node.Agents uses Cluster.connected/1 on trusted explicit target atoms; no string
  atomization, implicit connect, cache, registry, business input or retry. It owns
  only the aggregation. Internal retain/3 is @doc false, shared by production and
  the pathological whole-envelope vector; it is not a CLI identity API.
- Full result accounting reserves16KiB for all32 future static failure projections
  (255-byte names), rejects a whole overflowing authority with limit, retains partial
  classification and complete=false.128 agents per authority;32/8/5s/1MiB gates.
- TestBoot.authority/0 is an existing fixture which installs standalone authority
  after an interaction Node. Fixture alone now explicitly removes its non-authority
  responder first, preserving the existing delegation/disconnect assertions. No
  product runtime role switching was added. Restart test uses Supervisor terminate/
  restart_child rather than racing a permanent child's automatic restart.

## Transport decision and lifecycle

Installed source OTP29.1.2 kernel11.0.4 rpc.erl173-195/302, stdlib gen.erl549-556:
rex executes query in a spawned worker and replies through gen_server:reply using
ordinary sends. A suspended rex queue can admit late work. erpc spawn_request can
connect after a connected-set precheck. Supervisor rejected rex and approved one
Agent-owned supervised endpoint, minimal AuthoritySupervisor/Node integration and
bounded handshake; no second discriminator endpoint or new package.

All cross-node offers/confirms/heartbeat/replies use erlang.send with noconnect and
nosuspend. Reply aliases are disposable; local task death also deactivates them.
No remote monitors/links, remote group leader/IO, erpc/rex/cancel fallback. Controllers
and their workers only link/monitor locally. Endpoint callback never waits on Server
or Registry. Confirmation required before query admission; expired queued confirms
are rejected by endpoint-local offer deadline. Pending+active<=256; offer timers
are canceled on confirmation to avoid accumulating completed-offer timers.

Caller ownership uses Task.async_stream controller outside blocked receives; local
caller loss kills its task tree. Remote controller heartbeat lease250ms with50ms
renewal bounds cleanup after loss (normally<=300ms plus scheduling); max admitted
lifetime5s. Linked worker is killed and DOWN observed before controller returns.
No cross-node clock comparison or claim of instantaneous remote cancellation.
Passive queued messages may be handled after caller expiry, but cannot admit query
work without a live confirmation. This protocol requires matching library builds;
raw connected VMs without endpoint time out rather than falsely report empty Agent
inventory. Trusted distribution remains the security boundary, not a hostile-node
mailbox/RSS sandbox.

## Actual verification

Toolchain Elixir1.20.4 / OTP29.1.2; existing deps and _build inspected. Commands use
ERL_FLAGS='+S 2:2' only. Named invocations used Python-generated secure cookie and
unique --sname, explicit parent --cookie, inherited peer cookie; cookie never
printed. Finite timeout wrappers; no dependency installs/version changes.

- Format check `/tmp/discovery-format-check-frozen.log`: passed.
- Warning-fatal compile `/tmp/discovery-compile-frozen.log`: passed.
- Strict Credo `/tmp/discovery-credo-frozen.log`:103 source files, no issues.
- Umbrella `mix test --seed 631927`, `/tmp/discovery-umbrella-final.log`:181 ordinary
  tests: Harness35, Actions28, Runtime30, Agent9, Node60, Daemon5, CLI7, Web7.
  Named-only exclusions changed later by one new distributed test, without changing
  ordinary counts. CLI count includes1 doctest.
- Named `elixir --sname <unique> --cookie <secure> -S mix test --only distributed
  --seed 631927`, `/tmp/discovery-named-final.log`:22 actual tests: Runtime6,
  Node13 (7 existing+6 new discovery), Daemon2, CLI1. Includes existing native
  HTTP/workspace/model, delegation/partition/no-retry, and daemon role/boot tests.
- Affected ordinary final Agent9 + Node60 =69 (umbrella). Initial focused run65
  passed before additional edge tests; log `/tmp/discovery-focused.log`.
- New tests: creator exits and another lookup obtains same PID/incarnation and
  snapshot; identity-only projection with synthetic config AND credential markers;
  not_authority/not_found/unavailable/invalid distinctions; close/reuse expected PID
  stale and saved Ref unavailable; standalone Registry overflow explicitly limit;
  local/remote suspended Server caller loss and local deadline actual controller
  and worker DOWN BEFORE resume; remote authority supervised restart;32 targets
  accepted/33 rejected; ten real nodes observe max8 concurrent and one5s deadline;
  complete1MiB envelope budget with all32 failure reservations; caller-loss task
  tree actual DOWN while endpoint remains suspended; disconnect between validation
  and send, and before reply, no nodeup/reconnect/replay.
- Active LSP `/tmp/discovery-lsp/{output.log,lsp-results.json,lsp-transcript.json}`:
  all10 changed Elixir source/test files publishDiagnostics with zero diagnostics.
  Used existing cached OTP29.1.2 ElixirLS beams directly, bypassing installer launcher;
  fetchDeps=false, no cache cleaning or dependency repair. Initial probe incorrectly
  supplied multiple -pa paths under one flag and failed; corrected repeated -pa.
  Original `/tmp/discovery-lsp/initial-{output,stderr}.log` retained. Successful
  six-source probe retained separately before final ten-file probe.
- `git diff --check` + cached diff check passed: `/tmp/discovery-whitespace.log`.
  Boundary search `/tmp/discovery-boundary-search.log` shows only Node's own Cluster
  alias and local aggregation monitor; no Agent->Node/CLI/Daemon imports, :sys,
  get_state, erpc, String.to_atom, or Node.connect in new production seam.
  Core manifests/mix.lock were never written by this worker; no new dependencies.

## Initial failures retained separately

- `/tmp/discovery-initial-tests.log`:0/3 initial tests passed; missing APIs/endpoint,
  and invalid deterministic fixture credentials. Deterministic provider requires
  empty credentials; dedicated later OpenAI-compatible fixture covers secrets.
- `/tmp/discovery-first-source.log`:initial compile SyntaxError for comprehension
  inside tuple; parenthesized comprehension. `/tmp/discovery-source2.log`:2/3 passed,
  test controller introspection used wrong initial_call representation; corrected
  test to inspect its own endpoint active inventory. `/tmp/discovery-source3.log`:3
  passed. No Server private-state read introduced.
- `/tmp/discovery-credo-initial.log`:alias order and two excessive nesting findings;
  extracted bounded_request/discover_connected, final no issues.
- `/tmp/discovery-named-initial.log`:new discovery3 passed; existing Node test fixture
  failed when adding authority alongside the non-authority endpoint; fixture-only
  ownership correction above. `/tmp/discovery-named-second.log`:existing regression
  passed; new restart test raced permanent-child automatic restart (already_started).
  Corrected explicit supervised terminate/restart, no retry or relaxed assertion.
- `/tmp/discovery-named-third.log`:20 passed. `/tmp/discovery-named-fourth.log`:21
  passed after disconnect-before-send/reply vector. Final22 adds actual aggregate
  caller-loss task-tree DOWN gate. Distinct logs retained, no failure overwritten.
- `/tmp/discovery-extra.log`:4/5 Agent tests passed; synthetic HTTP config omitted
  mandatory allow_local_http. Replaced fixture URL with inert HTTPS example.invalid;
  query never invokes provider. `/tmp/discovery-extra2.log`:5 passed.
- `/tmp/discovery-umbrella-initial.log`:179 passed before additional vectors; final181.

## Freeze and index observations

Before writes retained status/index/worktree snapshots:
`/tmp/discovery-before-{status,index,worktree}`. Existing staged changes preserved.
Unknown actor subsequently staged discovery changes; supervisor notified, no
attribution/reversal. Worker executed NO add/stage/unstage/reset/restore/clean/
commit/push/merge/amend/branch or index-changing operation. noStagedFiles=false.
Mid/final snapshots `/tmp/discovery-{index-observed,worktree-observed,frozen-status,
frozen-index,frozen-worktree}` retained. Snapshots are observations, not an index
immutability claim; original untracked contents were not individually fingerprinted
before writes (tracked source differences retained in binary diffs).

Product/test/spec frozen13-path manifest `/tmp/discovery-frozen.sha256`, SHA256
60c099d16c12e8ce2c4e181d60f89222a2f5a1919585ba17ca1da24362873ce1.
Final source bytes are authoritative independent of external staging. Frozen
candidate is no longer edited; task execution/evidence/handoff notes written after
freeze only. Source dependencies fingerprints:

- Agent mix.exs850d7df280f31756bf2beb9015ec0b497a84b23a50bbad941a3da1cdb135515e
- Node mix.exsa4bb12842922b60e46652241ce0dac62839247c1d595079f8942c8a394b8b9e7
- mix.lockf847638301199181f2ca29b005766493b6f70d391639addc56d187196db422b7

## Residual risks / next owner

Independent check unchecked/pending; parent must review supervised endpoint seam,
no-connect audit and lifecycle proofs. Child is implemented, not independently
accepted. Endpoint/concurrency/lease limits bound application work, not an OS memory
cap or hard real-time scheduler guarantee. No physical/paid-provider acceptance.
No daemon/CLI product changes or release rebuild; accepted old daemon artifact is
stale after shared core changes. Final dual releases, stdin/reattach integration,
Dialyzer/Sobelow/xref/cumulative gates belong to CLI/parent. No commit/archive/journal.


## Admission blocker repair — separate candidate, awaiting independent recheck

The preceding181 ordinary/22 named results and original freeze describe the
historical candidate that FAILED independent admission review. They do not imply
repair acceptance. Original manifest `/tmp/discovery-frozen.sha256` remains
unchanged (SHA25660c099d16c12e8ce2c4e181d60f89222a2f5a1919585ba17ca1da24362873ce1).
Entry verification `/tmp/discovery-repair-entry-fingerprint.log` matched13/13.
All original scripts/failure/final/review logs were preserved, without overwrite.

Scoped repair changes Discovery, Discovery.Endpoint, owning Agent/Node discovery
tests, design.md and backend agent-orchestration.md. The independently minimized
reproduction was converted directly to public local/named tests BEFORE source
edits: helper DOWN/public timeout and suspended Server mailbox empty are verified
before endpoint resume, then zero NEW query calls and zero active controllers.
Red: `/tmp/discovery-repair-red-local.log`5/6 passed and
`/tmp/discovery-repair-red-named.log`6/7 passed; each failed only with one NEW call.
No broad diagnosis or recursive workers were used. No nearby GLOSSARY/ADR found.

Confirmation now starts only a passive controller; fresh admission ping/pong is
mandatory before Registry/Server work. Controller absolute deadline is captured
at endpoint processing, before its spawn. Requester uses one original deadline
allocated before stream startup; queued offer/ping/result processing checks it.
Admission/heartbeat pongs carry fresh remaining durations. Controller subtracts
its full local challenge roundtrip and clamps its existing deadline; it checks
lease/deadline again after dequeue, preventing stale queued responses renewing
budgets. Workers check their absolute deadline at startup and before Server call.
Transport still uses noconnect/nosuspend throughout; all production links/monitors,
group leaders and control sends stay local. Same endpoint and256 pending+active
quota, finite5s offer expiry, passive controller<=250ms lease plus scheduling,
original5s public/aggregate budgets. No retry/cache/dependency/host policy changes.

Final fresh repair verification (seed631927):

- `/tmp/discovery-repair-verified-focused.log`: Agent9 + Node3 =12 passed.
  Includes queued public confirm, expired delayed admission pong (short remaining
  duration and lease age),256 unanswered passive controllers retiring, delayed
  heartbeat pong retirement with actual worker DOWN before Server resume, and
  requester refusing an already-queued heartbeat after its own deadline. The last
  test suspends the stream timeout owner deliberately to isolate requester logic.
- `/tmp/discovery-repair-verified-named.log`: actual named discovery7 passed,
  including new queued-confirm test and existing no-connect/aggregation/lifecycle
  cases. Secure unique parent name and explicit random cookie, never printed;
  peers inherit cookie. ERL_FLAGS only '+S 2:2'. Partition-test global warnings
  occur in deliberate disconnect cases; all assertions pass.
- Original unmodified public/named probes rerun against repaired test beams:
  `/tmp/discovery-repair-original-{public,named}.log` each explicitly prints
  `NEW Server :ref calls after public timeout and helper DOWN: 0`.
  Each original script exits1 at its reproduction-only `calls == 1` assertion;
  wrapper asserts the zero-new-query signal, not exit status. Original scripts
  and original independent logs remain untouched.
- Final format, warning-fatal compile, strict Credo logs:
  `/tmp/discovery-repair-{format,compile,credo}-final.log`, all passed; Credo103
  files/no issues. Initial repair Credo log retained separately: copied probes'
  IO.inspect diagnostics triggered6 warnings; replaced with meaningful assertions.
- Active LSP `/tmp/discovery-repair-lsp-final/`: initialized server, disabled
  dependency fetching/Dialyzer, build completed4465ms, version1 diagnostics
  received for all10 candidate Elixir files, empty10/10. This is active LSP,
  not Dialyzer acceptance; missing Elixir source navigation is a tool limitation.
- Working/cached whitespace clean. Agent/Node manifests and mix.lock retain
  historical hashes above. Only focused tests and relevant named discovery suite
  rerun;181/22 broad counts remain historical, not repaired evidence.

Separate new candidate manifest `/tmp/discovery-repair-frozen.sha256` records the
original13 paths plus design and this evidence (15 paths); generated only after
all product/test/spec/evidence edits and final validation. Exact old/new hashes
and manifest SHA are in the external authoritative repair handoff. No further
product/test/spec writes permitted after that freeze. Independent read-only
recheck is pending; parent owns acceptance. Ordinary scheduling and distributed
races after timely liveness observation remain; no instantaneous remote-death or
hard real-time guarantee. Stale daemon artifact, dual releases/stdin and cumulative
analysis remain CLI/parent gates; CLI remains planning. No paid/physical/SSH work.

Index observation:83 staged paths remain. Unknown actor staged repair edits while
this worker ran (unstaged diff became empty); no attribution or reversal. Worker
made no index mutations, commits/push/branch/archive/journal/dependency operations.
noStagedFiles=false. Status/index observations preserved in
`/tmp/discovery-repair-{status,index-paths}`. Parent should retain these facts.
