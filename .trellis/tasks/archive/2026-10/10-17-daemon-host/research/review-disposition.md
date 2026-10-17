# Daemon independent review disposition and repair gate

## Decision

Parent fully read the independent report at:
`/home/kanade/.pi/agent/sessions/--mnt-data-Project-Beamlet--/subagent-artifacts/outputs/f7a9dedc-825c-4a6d-b777-91c560401e74/reviews/daemon-host-independent-check.md`.

Daemon acceptance remains BLOCKED; discovery must not start before repair and independent recheck. User implementation approval already covers these necessary fixes; no commit/index operations are authorized.

## Accepted findings

- F1/P2: Node only calls Runtime Limits.new for executor roles. Authority-only malformed limits bypass Daemon.configuration preflight and fail after child startup. Validate shared Runtime limits in Node for all roles, retaining executor-only report checks; do not copy a limit schema into Daemon. Assert direct safe preflight rejection, valid seven-role trees, and copied authority-only invalid limits static error without synthetic sentinel/cause.
- F2/P2: authority.stop throwing in the remote copied-service finally skips executor.stop. Guarantee both independent cleanups with bounded wait/kill and failure reporting. Add bounded Python fault-injection regression for first-service stop failure and second-service cleanup/log closure.

## Explicit candidate identity reconciliation

Parent accepts the **current multiline formatting** of scripts/deployment/check-release.sh as the starting point for repair. Read-only review recovered the exact original frozen bytes and established the entire delta is equivalent subshell formatting; no behavior change is identified. Do not restore/revert or mutate index. Provenance remains unknown.

- Old recovered frozen script: `/tmp/daemon-independent-mismatch/check-release.recovered.sh`, SHA256 `f1ef0412e474d393febc061d83170ca3e1294fa8140adbcc9d598b78a8a1d1ff`.
- Selected current script at review: SHA256 `e4556a0b76f6634b492216932e0f457dd9953aa9d975de70127ad3aa917d401c`.
- Exact delta: `/tmp/daemon-independent-mismatch/delta.diff`.
- Old frozen product manifest SHA256 `041dd03b9974f62ccb3e8d32ccc5fa3005b7fe8756fb0168946541892f70b3c0` and all old validation logs remain historical evidence, not new-candidate fingerprints. Do not overwrite them.

## Authorized repair boundary and checks

One trellis-implement writer owns the two repairs and necessary regressions/docs in the current cwd; no recursive dispatch. Node common preflight correction is the narrow prerequisite fix exposed by daemon requirements; no broader Node/Runtime refactor. Full discovery/CLI changes remain out of scope.

Use a **new** temporary evidence directory and new frozen manifest. Preserve original failures/success logs. Run affected Node/Daemon tests including seven-role validity, named daemon lifecycle, fault-injection Python regression, format/warning-fatal compile/strict Credo and relevant syntax checks. Rebuild one daemon artifact because Node source changes; rerun current copied three-mode/remote/rejection gate including the new malformed authority-only limits case. No need to repeat unchanged HTTP/Tool/full umbrella suites without a concrete new concern. Active LSP may be attempted for changed files; tool failure is inconclusive and does not authorize installer/dependency repair. Parent cumulative static/integration gates remain pending.

After repair, freeze product/test/spec, record actual validation counts/new artifact and source fingerprints, and hand off for an independent read-only recheck. Do not mark independent check passed or parent complete.
