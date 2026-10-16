# CURRENT independent child4 check — local scoped PASS

## Final scope disposition — user-approved removal

The user instructed: "取消跨物理主机验收这一要求, 继续开展后续工作".
This supersedes earlier pending/deferred physical-gate statements below. Child AC5
is removed; parent AC2/AC11 require the delivered multi-VM/release/deployment
evidence only. Physical testing was not executed and is not claimed. All remaining
implementation/check gates are accepted (123 ordinary tests;7 distributed tests at
two seeds; copied named release/closure/control checks). No source changed for this
scope reduction. Proceed to Phase3.4 commit plan, then archive/journal bookkeeping.
Earlier records below remain historical where they conflict with this disposition.

Fresh source/diff/script review and scoped fixes leave **no local blocker**.
Final123 nondistributed tests and7 distributed tests pass; distributed independently
ran seeds719916 and631927. Full evidence/commands/hashes and intermediate failures
are at the top of verification.md. Historical implementation findings follow below.

Fixed: rel hidden control VMs inherited the service port, breaking RPC/stop with
eaddrinuse; malformed CLI watch options; unenforced absolute trusted config path;
Python fixture whole-request/header lifecycle. Added durable copied named service
start/RPC/stop regression, closure required-edge checks, and CLI cleanup/dead-ref/
authority-loss coverage. No second loop, business retry or upstream code repair.
CLI output stays bounded; receipt deadline/control-call/terminal-IO limits are explicit.

Runtime barrier review passes: executor-clock post-release lease fence, bounded
observational polling, full capacity/zero tasks, submit-once and original success/
remote/no-fallback assertions preserved. Historical failure reason remains unknown;
the controlled stale-capacity probe proves only its own no_target ordering. No
Runtime edits requested or made by this reviewer.

ChildAC1–AC4/AC6 local delivery passes; ChildAC5 / parentAC2,AC11 physical gate
remains **PENDING**. Physical evidence template/runbook honestly require distinct
B/C hosts, marker evidence, role assertions, stop/loss/no fallback and teardown.
Live-provider smoke remains optional and unexecuted. Existing PLT analysis passed;
whole LSP coverage remains inconclusive. No residual review-owned VM/fixture found.
No specs/state/index/commit/manifest/lock/core-role writes. Parent owns final acceptance.

---

# Historical child4 implementation review notes

Local owned deliverables are implemented and ready for independent review. Full
integration acceptance is **blocked**, and no parent completion is claimed.

- Blocker (upstream owning seam): apps/beamlet_runtime/test/beamlet/distributed_test.exs:78
  expects the second immediate submission's Result.status to be :ok, but full
  distributed runs seed719916 twice return :error. Same-seed focused Runtime4 passes.
  The first remote-owner submission succeeds before the failure. A stale placement
  capacity report is a hypothesis, not a proved diagnosis: the assertion does not
  print safe Result.reason. Runtime owner should capture that reason, determine
  whether this is production admission behavior or missing readiness/capacity test
  barrier, repair only its seam and rerun explicit full distributed acceptance.
  Child4 made no Runtime edits or retries to conceal this result. Supervisor informed.
- External blocker: physical B/C distinct-host record remains pending; exact
  operator prerequisites are in physical-acceptance.md and deployment runbook.
- No new owned-source blocker found in manual review. CLI delegates directly to
  Agent, subscribes/acks/unsubscribes as the sink, caps events/output and surfaces
  timeout/loss without retries. Snapshot status is always queryable independently.
- Packaging: root backend build selector is necessary to exclude umbrella Web's
  optional Plug activation in Req. Isolated backend closure and copied boots pass;
  runtime external config is trusted local code read through Config.Reader.
  Default Web prod fail-fast and CSP remain intact without Web edits.
- Diagnostics: incremental clean feedback exists for CLI/integration tests/assets;
  config editor requires BEAMLET_CONFIG just like deployment; whole LSP sweep
  remains inconclusive. Existing-PLT Dialyzer0 errors is not a PLT refresh.

Current verification.md records commands, logs, counts, seeds, hashes, intermediate
failures and parent/child AC mapping. No paid provider, SSH credential search,
unauthorized remote deployment, staging, commits, archive or state changes.
