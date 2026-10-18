# Implementation plan

## Gate and ownership

- [x] User approved the final recreated planning summary with “批准”; task.py start succeeded and status is in_progress.
- [x] Before each dispatch, resolve task.py current and start the prompt with Active task: <returned path>; continue checking on subsequent dispatches.
- [x] Old run dccf558f-37f3-4b8a-a880-b89b315509d1 ended with a blocked report; parent read it. Prior erased code has no valid test evidence.
- [x] User explicitly instructed “不要新建worktree”. Use /mnt/data/Project/Beamlet on refactor/agent-core-extraction with one product writer. Previous run 1556925f-2b4f-47ca-aa13-2a85542421d1 is stopped with process terminal observed.
- [x] Rechecked primary branch/HEAD/status before rebuilding branch: dev at baseline, only task artifacts untracked. Stop on further unexplained workspace changes. Never rerun /tmp/extract_core.py blindly.

## Ordered work

1. [x] Load before-dev indexes/specs and current task artifacts; inspect actual source and tests, including durable references. Record baseline affected-test counts.
2. [x] Add beamlet_agent_core manifest, formatter and test setup; Agent dependency and backend_apps integration. No auto-start callback.
3. [x] Extract pure reducer while preserving Agent.Reducer adapter/contract, canonical digest ownership, normalized input safety and inherited/risk cases.
4. [x] Split source loading from pure context conversion; integrate existing ContextBuilder surface and preserve historical catalogue semantics.
5. [x] Extract existing pure reply/resume classifications into Core.Decision and integrate real Server/Durable call sites. Avoid broad execution redesign.
6. [x] Add meaningful Core tests for state replay, invalid transitions, source-bound context and deterministic decisions; retain integration assertions.
7. [x] Verify no forbidden Core imports/calls and that only committed events update the formal control state.
8. [x] Fixed independent review blockers F1–F3 and obtained independent recheck PASS (cb73e688); parent accepts AC1–AC7 within the recorded validation scope. See research/recheck-report.md and research/acceptance.md.
9. [x] Update backend directory/dependency and durable guidelines plus app docs.
10. [ ] Parent spec-sync review is complete; concrete commit plan is presented for approval. Commit/archive/journal remain pending Phase 3.4 confirmation.

## Verification

Run from umbrella root with the repository Elixir/OTP toolchain (nix develop when needed). Record unavailable prerequisites and excluded tests explicitly.

- mix format --check-formatted
- mix compile --warnings-as-errors
- mix test apps/beamlet_agent_core/test apps/beamlet_agent/test --seed 631927
- mix test --seed 631927
- mix credo
- mix credo --strict --all
- mix dialyzer (record PLT availability separately)
- mix sobelow
- mix gettext.extract --check-up-to-date
- BEAMLET_BACKEND_BUILD=1 mix compile --warnings-as-errors
- bash scripts/deployment/durable-e2e.sh
- Run isolated PostgreSQL durable/fork/history suites and named distributed/release checks as required by agent-durable, durable-references and backend-release specs; copy exact supported commands from existing fixtures, not invented arguments.

Planning-only recreation requires artifact/path/whitespace and manifest validation, not application tests. Do not claim old or erased implementation test runs passed.

## Review/rollback points

After each extraction step check diff and compile. Preserve callable surfaces/error precedence and all existing assertions. If scope requires event/storage/schema redesign, stop and revise planning. Revert only task-owned edits with reviewed patches; never reset shared worktree or delete unrelated files.

## Current execution evidence

Implementation is present in the authorized primary checkout. Core and Agent focused tests, no-start pure tests, and isolated PostgreSQL reference suites pass. Full umbrella passed 512 tests/37 excluded. Named/static/release/e2e gates passed; see research/implementation-report.md for final results. No commit/archive is performed by the implement child.

Final initial implementation gates: full umbrella 512 passed/37 excluded; named 35 passed/514 excluded; final focused Core 7 + Agent 106; isolated PostgreSQL reference suites 78; strict Credo/Dialyzer/Sobelow/catalogue/backend compile/copied releases/durable two-process e2e all passed. Evidence `/tmp/beamlet-acceptance.QYJ2am` and `research/implementation-report.md`. Independent review requested changes: F1 incremental context/error precedence and excess reads; F2 payload depth/replay consistency; F3 normalized inherited-source shape validation. See `research/review-report.md` for original findings and `research/fix-report.md` for repairs. Independent recheck PASS and parent acceptance are recorded in `research/recheck-report.md` and `research/acceptance.md`; only commit/archive remain pending.
