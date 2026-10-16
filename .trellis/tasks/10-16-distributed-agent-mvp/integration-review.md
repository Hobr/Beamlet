# Parent Integration Review — Revised Acceptance Passed

Parent disposition2026-10-16 after reading all accepted child handoffs and current
child4 independent evidence/source. No local implementation/check blocker remains.
User cancelled cross-physical-host acceptance. All remaining parent/child delivery
gates are accepted. Physical execution remains untested. Only final commit and
archive/journal bookkeeping remain open.

## Acceptance Matrix

| Parent criterion | Current disposition / evidence |
| --- | --- |
| AC1 independent boundaries | Accepted local: Runtime depends only on Actions/OTP; Harness independent26 tests; Agent translates native contracts; backend required dependency closure excludes Web. See children1–2 handoffs and child4 closure checks. |
| AC2 independent A/B/C nodes | Accepted: named three-role HTTP→workspace→model integration. Physical-host condition removed by user; no physical evidence claimed. |
| AC3 eligibility/capacity | Accepted local: child1 admission/pools/concurrent capacity; child3 roles/provider readiness; child4 wrong-environment/no-fallback. Discovery reserves no capacity. |
| AC4 lifecycle/honest uncertainty | Accepted local: Runtime fault/distributed cases, owner/cancel/deadline/admission loss and stale replies; child3 public guarded admission/lifecycle fixes. No automatic retry/replay. |
| AC5 compatible HTTP | Accepted local: Harness TCP/TLS wire/no-retry/redirect/size/error tests and child4 actual adapter integration. Optional live-provider probe NOT RUN. |
| AC6 constrained workspace | Accepted local: Harness path/nonregular/UTF-8/bounds/fd tests and executor-only marker through integration. Trusted-tree/TOCTOU limits preserved; no OS sandbox claim. |
| AC7 concurrent Agent Tools | Accepted local: child3 complete batch validation before dispatch, independent Tool concurrency, ordered ID joins and concurrent Agents. |
| AC8 collaboration | Accepted local: child3 asynchronous delegation/peer, nested cleanup, actual helper DOWN/retirement/restart fencing/late-reply tests. Waiting parents hold no execution capacity. |
| AC9 subscriptions/limits | Accepted local: child1 progress/retention and child3 ordered snapshot/credit/coalescing; child4 CLI invalid options/cleanup/event-limit/dead-ref/loss coverage. No replay promise. |
| AC10 deployable backend/Web preservation | Accepted local: backend .rel/.app/lib closure, copied authority/executor named service boot/RPC/stop without Web/model secrets; fixed service and ephemeral control ports; default prod missing-secret rejection and Web7/CSP pass. |
| AC11 deployment documentation and automated record | Accepted: runbook/scripts and independent-VM/copy-release record delivered. Physical-record requirement removed by user. |
| AC12 checks and final review | Checks and final revised-scope integration review accepted below. LSP coverage inconclusive; existing-PLT analysis does not establish refreshed PLT. |

## Final Local Evidence

Child4 independent review run54d4ac33-257d-47c9-90ea-3f62faa95a52:
123 nondistributed tests seed631927 (Harness26/Actions5/Runtime28/Agent4/Node53/Web7);
7 distributed tests each seed719916 and631927 (Runtime4/Node3); compile/format/
strict Credo/existing-PLT Dialyzer; isolated backend build and copied closure/named
role/RPC/stop checks; Web secret fail-fast; bounded fixture socket/header/cleanup.
Unchanged Sobelow/dependency/xref evidence is retained in child4 verification.md.
No review-owned named VM/fixture remains. Exact commands/logs/current hashes:
`../10-16-backend-release/verification.md`; review findings:
`../10-16-backend-release/check-report.md`.

Independent review repaired release control-port collision, CLI watch validation,
absolute trusted config enforcement and Python whole-request deadline. These remain
within child4 scope. Runtime aggregate test repair was separately scoped and reviewed
unchanged: observe actual gateway release then newer eligible Directory lease before
one second submission. Controlled stale-capacity probe produced no_target; original
historical failure reason was not recorded and remains unknown. See
`../10-16-backend-release/aggregate-runtime-repair.md` (Runtime32 and aggregate7/7).
Prior intermediate failures are preserved; they are not current passing evidence.

## User Disposition: Physical Acceptance Removed

The user instructed: "取消跨物理主机验收这一要求, 继续开展后续工作".
This explicitly supersedes the earlier deferral. Child AC5 is removed and physical
portions of parent AC2/AC11 are no longer delivery gates. Parent accepts the revised
scope on the recorded independent review evidence. No physical execution occurred.

## Remaining External Prerequisite (for future resumption)

Need B authority and C executor on distinct physical hosts, compatible release,
reachable long names/private EPMD and fixed distribution ports, operator-provisioned
cookie and trusted absolute configs, C-only permitted marker tree. Use local fixture
on C to avoid paid requests. No SSH/private credential search or remote deployment
is authorized by having scripts. Obtain operator host identities, access method and
deployment instructions before using external machines; never ask for secrets in chat.
Fill `../10-16-backend-release/physical-acceptance.md` with observed identities,
marker digest, explicit B authority, stop/loss/no fallback and teardown. This optional
future record is not a completion gate; never claim physical execution without it.

## Spec Synchronization

Parent published backend-release.md and synchronized backend index/directory/Agent/
quality specs. Prior operation-runtime/harness-providers/agent-orchestration contracts
remain authoritative. No business persistence, retry, consistency, UI or sandbox
scope expansion. Final commit/finish-work bookkeeping remains deferred to delivery;
user SBOM commit and unrelated/index work are preserved.
