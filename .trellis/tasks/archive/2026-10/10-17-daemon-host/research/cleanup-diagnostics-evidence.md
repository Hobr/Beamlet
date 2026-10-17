# Cleanup diagnostic repair — frozen candidate, independent recheck PENDING

Residual F2/P2 is self-fix verified only. Daemon acceptance remains blocked pending parent independent recheck; no discovery/task activation or READY claim. Prior F1 and both-service cleanup execution were independently verified and were not changed.

## Narrow correction and regression

`report_cleanup_failures` previously transferred only exception type/message; `str(exception)` excludes existing `__notes__`. It now copies each transferred service exception's existing notes to the final primary after its existing summary. The original RPC exception object remains primary; absent an RPC error, the first cleanup exception remains primary. No cause/context rendering, process-management, timeout, service order, startup or business changes were made. All diagnostic inputs in the new tests/probe are safe synthetic failures; no config, cookie or key is added to output.

The original four tests remain. Two composed tests add both-service stop and fallback-wait failures, with and without an active RPC error. They assert every stop/fallback diagnostic in the final exception/traceback, original identity, both stop commands, both kill/five-second-wait calls and both closed logs. README now explicitly requires Python 3.11+ for sys.exception/add_note and records Python 3.14 regression validation. No provisioning change.

## Actual bounded checks

New evidence: `/tmp/beamlet-daemon-cleanup-diagnostics-evidence/`. Every Python validation used `PYTHONDONTWRITEBYTECODE=1`, `python3 -B`, and a finite timeout. No checkout bytecode was produced.

- Exact independent probe `/tmp/daemon-repair-independent/composed-cleanup-probe.py`: before exit1, missing fallback-A/B despite passing original-identity and both cleanup assertions; `probe-before.log`. After exit0, every diagnostic visible; `probe-after.log`. Original probe and failed historical log remain untouched.
- Affected Python suite: before **6 run, 4 passed, 2 expected failures**, missing fallback-A with RPC and fallback-B without RPC; `tests-before.log`. After **6/6 passed**, 0.004s; `tests-after.log`. Command: `PYTHONDONTWRITEBYTECODE=1 timeout 10s python3 -B scripts/deployment/test-check-named-release.py`.
- Both affected Python files AST-parse; Python **3.14.7**; `syntax.log`. No shell source changed; no shell execution required.
- Cached and uncached `git diff --check` pass. Preservation and frozen-byte verification pass; `preservation-final.log`.
- No Elixir suite/compile/Credo/build/copied gate rerun: only diagnostic-note transfer changed. Prior 22-path/artifact validation remains historical applicable evidence, not a new execution claim.

## Candidate identity and preservation

Parent corrected the requested count: historical manifest already includes README. New manifest retains the **same 22** product/test/spec/doc paths, not an artificial 23rd entry. Task artifacts remain separate.

- New manifest: `/tmp/beamlet-daemon-cleanup-diagnostics-evidence/product-test-spec.frozen.sha256`; SHA256 **13afbf11e88c485e38cb0b92fa266092cbc7b2200d74be32b0abbdffc6f62eb9**. Product/test/docs frozen; no further edits absent parent authorization.
- Historical manifest0946a6cf94ab5c0024d2af0d774fed0daed479a68d6340111dea77f834e641ab remains untouched. Entry verification matched22/22.
- Unchanged `_build/backend/prod/rel/beamlet_daemon`: all1003 recorded file contents match; shell-sorted manifest fingerprint **08cdf56b28a7064764952c620f682495d207e4d921604e98e82a8e56d4914eaf**. New evidence retains identical `source-artifact-shell.sha256`; no release rebuild.
- Removals remain absent: `config/backend_runtime.exs`, `scripts/deployment/node.example.exs`.
- Parent-selected `check-release.sh` unchanged: **e4556a0b76f6634b492216932e0f457dd9953aa9d975de70127ad3aa917d401c**.
- Entry snapshots before writes: `source.before.json`, `status.before`, `index.before`, `git-index.before`, `worktree.before`, `inventory.before`. Final counterparts/preservation log retain the exact allowed delta. All old /tmp evidence remains preserved.
- Cached binary diff remains **50ed2d51ee96ea20d9d068c4cee83da95486a709c913d435a7bb1cfbf23f6ec1**; raw index remains **136cfc3db06efbf5b9572fa9a97f68bc37b6036971f285495757f3cf9d0f15fb**. Existing staged work preserved; noStagedFiles=false. No index operation or unexplained source mutation observed.

Only three product/doc paths changed: named checker, its regression fixture and deployment README. This new durable note and the appended implement.md status are task artifacts. No Node/daemon/Runtime/business/spec or check-release.sh edits, dependency operations, journal/archive, physical/SSH/paid work occurred. LSP remains historically inconclusive; parent cumulative static/integration and final CLI/discovery gates remain pending. This repair does not independently accept daemon.
