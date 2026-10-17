# Node-library implementation evidence

## Candidate and scope

- Baseline `0fed1b1`, branch `dev`, cwd `/mnt/data/Project/Beamlet`.
- Approved library/host seam implemented; parent has frozen product/test/spec for independent read-only checking. Independent check is **pending**, not attested by this implementation note.
- No Agent orchestration, credentials, model binding, Runtime admission, release/config/scripts, daemon policy, discovery API or full CLI session changes.
- Both generated host Applications remain unchanged, empty and side-effect-free.

## Changed paths

- Removed `apps/beamlet_node/lib/beamlet/node/application.ex` and Node's `mix.exs` application callback; updated `node.ex` module description only. All existing explicit Supervisor/configuration APIs remain.
- Added `apps/beamlet_node/lib/beamlet/node/cluster.ex`, `test/beamlet/cluster_test.exs`, `test/beamlet/cluster_distributed_test.exs`; strengthened `test/beamlet/node_test.exs` to actually start/stop all seven combinations and run the local model/Gateway test with all three roles.
- Moved old Node terminal adapter to `apps/beamlet_cli/lib/beamlet/cli/client.ex`, terminal tests to `test/beamlet/client_test.exs`, and real HTTP/workspace integration to `test/beamlet/release_integration_test.exs`. No old namespace forwarding.
- Added CLI-owned `test/support/boot.ex` and `test/beamlet/library_loading_test.exs`; updated CLI `mix.exs` explicit Node/Agent and test-only Runtime/Harness/Jason dependencies and test support path; excluded distributed tests in CLI test_helper. Node has no consumer/host dependency.
- Narrow current-stage spec updates: backend `index.md`, `directory-structure.md`, `agent-orchestration.md`, `error-handling.md`, `backend-release.md`. Old release assets explicitly described as pending, not current acceptance evidence.
- Child `implement.md` honestly checked; this research note added. Full changed-product list: evidence directory `changed-product-paths.txt`.

## Interface handoff

- Embed `{Beamlet.Node, options}` explicitly; fixed registered names still mean one Node per VM. `start_link/1`, child_spec, `configuration/1`, `profile/1`, `catalogue/0` and all seven nonempty role sets are unchanged.
- `Beamlet.Node.Cluster.authority(name, allowed)` -> `{:ok, node_atom}` or `{:error, :invalid_authority}`. Validates **whole** list (max32), ASCII node@host names (max255 bytes), then atomizes only a matching trusted name. Invalid/improper lists reject safely.
- `Cluster.connect(name, allowed)` -> `:ok` or `{:error, :invalid_authority | :unavailable}`. One helper/one attempt; Task stream controller bounds wait at5000ms and cleans helper on timeout/caller loss. This is not network rollback: OTP may complete an initiated handshake later. No business retry/background reconnection.
- `Cluster.connected(allowed)` -> `{:ok, sorted_node_atoms}` or `{:error, :invalid_authority}`. Filters currently connected visible/hidden nodes; local VM included only if named/distributed and allowlisted. Does not atomize allowlisted strings or connect implicitly.
- `Beamlet.CLI.Client` owns create/input/snapshot/status/stop/close/watch. Original sink-local subscribe/consume/ack/unsubscribe, 60s receive budget,256 event ceiling,4096 displayed-codepoint cap, terminal behavior and explicit errors are preserved. Agent remains the owner of all business controls.
- Preserved integration assertions include real HTTP authorization/body separation, workspace marker correlation, subsequent turn/fresh-capacity fencing, wrong environment/no fallback, stop during held HTTP, executor loss/no replay, and dead refs/watch cleanup.

## Toolchain and validation

Full retained logs: `/tmp/beamlet-node-library-j8l5eF/` (temporary evidence directory; not committed). OTP29.1.2 / Elixir1.20.4; dependency inspection succeeded; bounded `ERL_FLAGS='+S 2:2'` used. No dependency versions or root lockfile changed.

| Command / scope | Result / log |
| --- | --- |
| `mix deps` | passed; `deps.log` |
| `mix format` then `mix format --check-formatted` | passed; `format-apply.log`, `format-final.log` |
| `mix compile --warnings-as-errors`, then forced full `mix compile --force --warnings-as-errors` | passed; `compile-initial.log`, `compile-final.log` |
| `mix test --seed 631927` | **169 passed**, including2 doctests;14 distributed excluded; `test-initial.log` |
| Actual named distributed selected files, corrected invocation below | **14 passed** (Runtime6, Node7, CLI1), zero failures; `distributed-corrected.log` |
| `mix credo --strict` | initial migrated alias-order finding fixed; final95 source files/727 mods-funs, no issues; `credo-initial.log`, `credo-final.log` |
| `git diff --check` and `git diff --cached --check` | passed; `diff-check.log` and captured tool output |
| Active product old namespace/boot search | zero matches; `obsolete-active-source-references.log` |
| Active LSP attempts | **inconclusive**, not clean; see below |

Ordinary breakdown (including doctests): Harness35, Daemon2, Actions28, Runtime30, Agent4, Node56, CLI7, Web7 =169. The ordinary run did not require hosts, named VMs or stdin. Lifecycle error logs are expected existing loss-test output, not test failures.

### Exact named invocation correction and failure evidence

Initial launch used a random cookie through inherited `ERL_FLAGS='+S 2:2 -setcookie <secret>'`; existing Runtime/Node and migrated CLI failed with invalid challenge replies (13 failures, only the stalled-handshake test passed). Retained `distributed-initial.log`; do not mistake it for a business failure or erase it.

A minimal standard-IO Erlang peer probe compared cookie equality without printing values:
- Inherited flags mode: parent matched requested value; parent/peer **mismatch**, connect=false.
- Explicit parent `--cookie` with scheduler-only ERL_FLAGS: parent matched requested value; parent/peer **match**, connect=true.
- Evidence: `cookie-probe-flags-otp.log`, `cookie-probe-explicit-otp.log`. This proves invocation-induced mismatch; it does not speculate about undocumented OTP duplicate-option parsing.
- Initial diagnostic probes used Elixir `Node.get_cookie/0` on a code-path-free Erlang peer and hit undefined function; retained separately as `cookie-probe-flags.log`, `cookie-probe-explicit.log`. Corrected probe used `:erlang.get_cookie/0`.

Successful invocation (cookie securely generated in the launcher, never printed; unique name):

```sh
ERL_FLAGS='+S 2:2' elixir --sname <unique-node> --cookie <secure-random-cookie> -S mix test \
  apps/beamlet_runtime/test/beamlet/distributed_test.exs \
  apps/beamlet_node/test/beamlet/distributed_test.exs \
  apps/beamlet_node/test/beamlet/delegation_binding_test.exs \
  apps/beamlet_node/test/beamlet/cluster_distributed_test.exs \
  apps/beamlet_cli/test/beamlet/release_integration_test.exs \
  --only distributed --seed 631927
```

Peers already pass `Node.get_cookie()` explicitly. No source security policy, business assertion, retry semantics or peer infrastructure was changed to resolve the launch error. Parent approved this bounded diagnosis before continuation.

### LSP limitations

Mutation-triggered Pi-lens probes reported clean for the new Cluster source/test in some turns but unavailable/unparsed checks for migrated CLI paths; these partial events do not establish overall coverage. A standalone active `elixir-ls` initialization attempt targeted13 changed Elixir paths, but its own installer reported missing/lock-mismatched vendored dependencies and timed out before initialize/didOpen completed. It was terminated with only its own process group cleaned up; no repository dependency repair attempted.

All13 paths are recorded as **inconclusive**, not zero-diagnostic clean. Logs: `probe-lsp.py`, `lsp-probe.log`, `lsp-results.json`, `lsp-stderr.log`, `lsp-transcript.json`. A separate Pi-lens CLI entrypoint was unavailable due missing `@earendil-works/pi-tui`; no workaround/install attempted. No LSP success is inferred from an empty cache.

## Index safety / residual issues

- Worker executed **no staging/unstaging/commit/push/reset** operations. Initial staged snapshot saved as `git-status-before.txt`, `staged-before.diff`, `staged-before.sha256` (`027f678e694f5a51e2a754dc1aa556d4679c6660601b48a3390d91510e363d06`). This is the worker-start snapshot, not the earlier planning research fingerprint.
- Later observed expected task code/test/spec changes moved into index; actor **unknown**. Parent independently confirmed expected paths and empty working diff at freeze. Worker did not restore/alter index; staged changes exist and **noStagedFiles is false**.
- Frozen cached fingerprint: `d5c0e53d1ec414ead03284257bd1529d03d883b97b600fefe42db1b6fa047150`. Saved status/cached+working summaries and current source bytes: `git-status-final-observed.txt`, `cached-diff-final.stat`, `working-diff-final.stat`, `staged-final-observed.diff`, `staged-final-observed.sha256`, `source-fingerprint.sha256`. Subsequent worker writes are limited to this note/checklist/handoff.
- Independent check remains pending. Active LSP is inconclusive. Old Node release/config/scripts deliberately remain obsolete until daemon-host; release gates were **not run** and no new copied release is claimed. Discovery/session/release integration are subsequent child deliverables.
- Fixed VM-global names remain intentional. Named tests use same-host peers, not physical multi-host or paid provider acceptance. No physical deployment or paid API executed.
