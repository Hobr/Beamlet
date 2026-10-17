# Daemon review repair evidence — frozen for independent recheck

F1/P2 and F2/P2 are **self-fix verified**. Parent independent recheck and daemon acceptance remain pending. Child remains in_progress. This supersedes no historical validation: `implementation-evidence.md`, prior reviewer snapshots, recovered script and `/tmp/beamlet-daemon-evidence/` remain untouched.

## Boundary and diagnosis

F1: Node previously invoked `Limits.new(runtime)` only in the executor branch. Authority-only configuration could return children and later fail in Runtime after Routes started. Node now invokes that existing common validator for every role set before returning children; Report validation remains executor-only. No daemon limit schema or Runtime schema/refactor was added. Direct Node and daemon tests assert safe error returns for 13 invalid vectors: zero, refresh upper bound, executable byte floor/ceiling, unknown key, atom, nil, tuple, wrong-key map, wrong value type, sentinel binary, malformed proper list and improper list. These are configuration-function assertions before any child start, with Routes/Directory/Registry absence as supporting assertions. Existing tests still actually start seven role trees and complete the local three-role Gateway turn.

F2: sequential remote `authority.stop(); executor.stop()` let the first failure skip executor cleanup. `stop_services` attempts each independently and reports failures after cleanup. Service.stop separately attempts bounded stop (10s command /10s wait), kill/5s wait and log close, retaining its first error and attaching further failures as exception notes. An active startup/RPC error remains primary and receives cleanup notes. No paid/physical process is needed for injected regressions. Four Python tests exercise exception/timeout/nonzero first-stop failure, fallback-wait timeout, both-service failures and existing RPC failure; both logs close and second-service stop/kill/wait are observed.

Copied rejection adds authority-only malformed limits containing a synthetic sentinel. It requires the static daemon error, Config.Reader failure (before application/role supervision), no sentinel/raw runtime-limit cause and no failed-child startup message. This proves preflight rejection rather than inferring it from processes disappearing after late failure.

## Actual execution

New evidence directory: `/tmp/beamlet-daemon-repair-evidence/`.

| Gate | Actual result / log |
| --- | --- |
| Before-fix focused Node/daemon regression | Each app 4/5 passed, one new preflight test failed; `preflight-before.log` |
| Before-fix original-index Python control-flow repro | First-stop RuntimeError reproduced skipped second cleanup; `teardown-before.py`, `teardown-before.log` |
| `ERL_FLAGS='+S 2:2' mix test apps/beamlet_node/test apps/beamlet_daemon/test --seed 631927` | Node57 + Daemon5 = **62 passed**,9 distributed excluded; `ordinary-final.log` |
| Named daemon bootstrap lifecycle | **2 actual passed**, seed631927; `named-final.log`; explicit secure parent --cookie generated without output and scheduler-only ERL_FLAGS |
| Bounded Python subprocess regression (10s timeout) | **4 passed**,0.003s; `python-final.log` |
| Both Python AST syntax; shell bash -n for check-release/check-local | Passed; `python-syntax.log`; shell command exit0 |
| `mix format --check-formatted` | Passed; `format-final.log` |
| `mix compile --force --warnings-as-errors` | Passed all8 apps; `compile-final.log` |
| `mix credo --strict` | Passed97 files/747 mods-funs, no issues; `credo-final.log` |
| `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite` | Passed; `build-final.log` |
| Current selected `bash scripts/deployment/check-release.sh` with scheduler-only ERL_FLAGS | Passed copied closure,3 modes/default9100/RPC/pid/stop,2 remote only services19101/19102, restricted remote Gateway turn, failed-peer continuation and12 rejected starts; `release-frozen.log`, `copied-frozen/*` |
| Whitespace and22-path frozen SHA256 verification | Passed; `frozen-bytes-check.log` |

The earlier copied pass is retained as `release-final.log` / `copied-final/*`. The final pass reran after strengthening the checker to explicitly assert Config.Reader rejection, using the same rebuilt release. No additional release build or whole-umbrella/HTTP/distributed rerun was necessary. The unchanged full suites retain historical evidence only.

## Exact candidate identity

Product/test/spec are frozen; **no further product/test/spec edits without parent authorization**.

- New22-path manifest: `/tmp/beamlet-daemon-repair-evidence/product-test-spec.frozen.sha256`.
- Manifest SHA256: **0946a6cf94ab5c0024d2af0d774fed0daed479a68d6340111dea77f834e641ab**. It includes the previous19 extant daemon candidate paths plus Node source/test and Python regression. The two historical removals remain absent.
- Source artifact: `_build/backend/prod/rel/beamlet_daemon`.
- Source artifact and copied artifact shell-sorted1003-file manifests are byte-identical; SHA256 **08cdf56b28a7064764952c620f682495d207e4d921604e98e82a8e56d4914eaf**. Retained `source-artifact-shell.sha256` and `copied-frozen/copied-manifest.sha256`; fingerprint is a relative-file/content manifest hash, not a tarball hash.
- Initial Python codepoint-sorted source artifact manifest (`source-artifact.sha256`, hash75bbc311...) had a different ordering from locale shell sort. Comparing all1003 path/content mappings found zero differences; rerunning the exact shell sorting produced the identical copied hash. `freeze.json` records both forms. No artifact/source discrepancy exists.
- Parent-selected multiline `scripts/deployment/check-release.sh` remains **e4556a0b76f6634b492216932e0f457dd9953aa9d975de70127ad3aa917d401c**; unchanged by this worker and actually executed in the final gate. Old recovered f1ef0412... bytes and unknown provenance remain historical; no index reconciliation was performed.

## Changed paths (this repair only)

- `apps/beamlet_node/lib/beamlet/node.ex`
- `apps/beamlet_node/test/beamlet/node_test.exs`
- `apps/beamlet_daemon/test/beamlet/daemon_test.exs`
- `scripts/deployment/check-named-release.py`
- `scripts/deployment/test-check-named-release.py` (new)
- `.trellis/spec/backend/agent-orchestration.md` (common preflight ownership clarification)
- `.trellis/tasks/10-17-daemon-host/implement.md` (repair handoff note)
- `.trellis/tasks/10-17-daemon-host/research/repair-evidence.md` (this note)

## Preservation and remaining gates

Entry snapshots `status.before`, `index.before`, `worktree.before`, `inventory.before`, `source.before.json` were taken before edits. Final product observation uses corresponding `.frozen` files. Cached binary diff is byte-identical, SHA256 **ace7418eac6add91849484218668f009dbe355f6a2165349f3e8a43da9a73609**. Only the five expected preexisting product/spec paths changed; new Python regression and task notes are deliberate. No unexplained product change observed. Existing staged changes were preserved; **noStagedFiles=false**. No forbidden Git/index mutation, install/version update, journal/archive change, or modification of old evidence. The test import produced a new local __pycache__; only that generated file/directory was removed.

Automatic changed-file diagnostics initially flagged the Python optional ModuleSpec/loader guard and import ordering; corrected before final validation. Prior LSP initialization/dependency failure remains **inconclusive**; no comprehensive new active-LSP clean claim or tool repair/cache clearing. Parent cumulative Dialyzer/Sobelow/xref/two-host/stdin/reattachment gates remain pending. Independent recheck must verify this newly frozen candidate; self-fix verification is not independent acceptance. No discovery/CLI feature work, role switching, retries/replay, key fallback, SSH, physical deployment or paid provider execution.
