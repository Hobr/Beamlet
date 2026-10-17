# Final parent acceptance — Node / daemon / discovery / CLI

## Disposition

Parent AC1–AC9 are accepted for the delivered candidate. All four children passed
implementation and independent review in order: Node → daemon → discovery → CLI.
CLI review initially BLOCKED three real defects; its separately frozen repair
received independent READY. No remaining actionable P0/P1/P2 finding was reported.
This is product/quality acceptance, not a commit, deployment or archive action.
The parent remains a coordinator; child task statuses remain in_progress until
archive. User subsequently approved the refined nine-commit batch; execution is
recorded in research/commit-execution.md. Archive/journal remain deferred.

## Evidence chain

- Node: `../../10-17-node-library/research/implementation-evidence.md`; independent
  report `outputs/c36ffa48-d2c2-4f47-82d1-62506c02f3c1/reviews/node-library-independent-check.md`.
- Daemon: `../../10-17-daemon-host/research/review-disposition.md`; final report
  `outputs/273eb355-89ef-4bf8-98a9-ca43a487cbe7/reviews/daemon-cleanup-diagnostics-final-check.md`.
- Discovery: `../../10-17-agent-discovery/research/review-disposition.md`; repaired
  admission report `outputs/010f066f-2caa-472e-a8ce-64e4b5119462/reviews/agent-discovery-admission-recheck.md`.
- CLI: `../../10-17-cli-host/research/review-disposition.md` and
  `../../10-17-cli-host/research/review-repair-evidence.md`; full final independent
  report `outputs/5663d550-4f1a-4a4c-a9c1-bbc267a9d0d8/reviews/cli-host-review-recheck.md`.

Report paths above are relative to
`/home/kanade/.pi/agent/sessions/--mnt-data-Project-Beamlet--/subagent-artifacts/`.
Durable task notes retain the outcome if retention-managed reports expire.

## AC1–AC9 review

| AC | Accepted behavior and evidence |
| --- | --- |
| AC1 | Node is callback-free; explicit embedding only. Original independent fresh-VM probes and final loading tests prove no roles/config/stdin on dependency startup. |
| AC2 | All seven role trees run, including triple-role Gateway model input. Shared libraries have no host dependency. Final Node60/Web7 and named suites preserve Web behavior. |
| AC3 | The same copied daemon artifact starts in default dual-role, authority-only and executor-only modes, with named role assertions/RPC/pid/stop. Interaction rejects; bootstrap/remote Gateway/config-failure checks pass. |
| AC4 | Copied foreground CLI commands connect/create/find/attach/input/watch/status/stop/close. Ref identity survives quit/EOF/detach; loss never implies closure. Independent real PTY exact-byte/encoding restoration and model marker prove actual Unicode dispatch. All retained identities are reachable through pagination. |
| AC5 | Both rebuilt artifacts pass closure, trusted runtime/config isolation and named service/control checks outside checkout/deps. Each excludes the other host and Web; neither requires Web secret. Ucwidth is present and actual copied Owl width behavior executes. |
| AC6 | Old CLI/Application/boot/release removed; owning tests and HTTP integration migrated. Parent final search of apps/config/rel/scripts/README/mix/spec finds only a descriptive removal reference in the spec, no executable legacy entrypoint. |
| AC7 | Final aggregate196 ordinary/23 actual named passes, including native HTTP→workspace→model, no fallback, fresh capacity, held-request stop and executor loss/no replay. Static/build/copied gates and historical failures are recorded below. |
| AC8 | Empty ordinary host trees, explicit startup-only roles and no runtime switching remain verified. Future Web integration is demonstrated by triple-role library composition; no Web feature added. |
| AC9 | Copied independent A/B/C sessions preserve full authority/ID/PID/incarnation across quit/EOF; explicit close yields not_found. Shared multiple-authority/race/reuse/partial/disconnect and admission-helper cleanup tests remain accepted. Fresh live token tests attach exact Refs including NUL/control/max/reserved IDs, then reuse an ID without rebinding the old alias or killing the replacement on quit. |

## Final verification and limits

Authoritative final full run: `/tmp/beamlet-acceptance.OtC5Em`;
`/tmp/cli-host-repair/check-local-final.exit` is0. Ordinary196 = Harness35,
Actions28, Runtime30, Agent13, Node60, Daemon5, CLI18, Web7. Actual named23 =
Runtime6, Node14, Daemon2, CLI1, seed631927. Ordinary excluded23 distributed tests
are not counted as executed. Format, warning-fatal compile, strict Credo108 files/
877 mods-funs, existing up-to-date PLT Dialyzer0 errors/0 skipped, Sobelow and both
isolated release rebuilds pass. No forced PLT refresh. Xref reports five cycles;
this is not a claim of acyclicity. Six Python cleanup/nested-diagnostics tests,
expected Web prod missing-secret failure and Web CSP assertions pass.

Independent final review adds15 focused existing-beam tests, nine genuine PTY
cases and a secure named exact-Ref live probe. Fresh copied checker finished all
assertions and its success marker with no traceback; its async launcher retained
no OS exit-status marker, so no separate exit0 is invented. The authoritative
full aggregate does have an explicit exit0. Active version1 empty diagnostics
for five final repair-relevant paths were audited; earlier timeout/initialization
failures remain historical inconclusive evidence, not clean coverage claims.

Historical191/23 candidate and two intermediate196/23 aggregates failed new CLI
checks and remain failures; they are not substituted for final acceptance.
Original red regressions/old-beam PTY corruption evidence remain separately stored.

Frozen reviewed manifests under `/tmp/cli-host-repair`:

| Manifest | Files | SHA256 |
| --- | ---: | --- |
| source.frozen.sha256 |166|1fbf9d98e6e2842ce89c486e264d82a0aff8c14cf4485fdcdf5b3f5f6d752ac4|
| daemon-artifact.frozen.sha256 |1006|035572d3a3d489779310aa9eb6a7fa17b79fdda52795542305d33e250da481f8|
| cli-artifact.frozen.sha256 |1036|9d759c8fc0d6f665551c386bd305c72408a9a5ebcbb7d622d376ec3758ea3290|

All matched before/after independent review; copied inventories also match.
Parent acceptance subsequently changes documentation only: backend-release spec,
parent PRD/implement/execution-status and CLI PRD/implement/review-disposition plus
this report. The old reviewed source manifest is retained unmodified. Final
comparison finds exactly two changed entries: backend-release spec and CLI PRD
acceptance checkboxes. A first comparison expected only the spec and rejected the
additional PRD delta; the corrected explicit two-document comparison passes.
All1006 daemon/1036 CLI artifact files remain byte-identical; both whitespace
checks pass. No application/test/config/script change follows independent READY.

## Operational assumptions and deferred actions

The terminal reader requires exclusive ownership during temporary encoding setup;
all captured options are restored. Discovery is eventual; explicit authority+ID
attach selects current identity while saved Refs stay original. Config is trusted
executable code, distribution is trusted, and stop/watch do not prove upstream
rollback or stopped billing. No physical-host or paid-provider acceptance claimed.

Unknown external staging changed99 to100 paths during review; no ownership
attribution, reconciliation or unchanged-index claim is made. Unrelated .gitignore
and staged/unstaged/untracked work are preserved. No index mutation, branch change,
commit, push/amend, archive or journal action is performed by this acceptance.

User requested finer splitting of the initial two-commit proposal. The revised
nine-commit plan, ordering, exact shared-file ownership and intermediate release
migration caveat are recorded in commit-plan.md. No rejected candidate is
reintroduced merely to manufacture fix commits; owning tests remain with changes.

User subsequently replied “确认” to the refined proposal, authorizing scoped
staging and nine commits. Execution and validation are recorded in commit-execution.md.
Unknown .gitignore changes remain excluded. No push/branch/archive/journal action
is authorized by that commit approval.
