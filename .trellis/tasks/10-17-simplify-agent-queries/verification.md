# Implementation verification — retained summary

Implemented and independently reviewed on dev HEAD9657d2a. User acceptance and scoped cleanup are complete; see [acceptance.md](acceptance.md), [independent-review.md](independent-review.md) and [cleanup.md](cleanup.md). No stage/commit/push/archive was performed.

## Retention status

After accepting the implementation, the user requested cleanup of the remaining intermediate files. On2026-10-17, validation/ and independent-evidence/ were removed, including successful/failed logs, command records, named launchers, source-hash inventory and generated handoff data. Their original records are no longer provided. Counts and exits below are retained historical summaries, not newly executed checks or links to readable raw output. Product regression tests remain under apps/; their execution does not depend on those task-local scripts.

## Delivered behavior

Discovery uses fixed OTP erpc calls remotely and disposable OTP Task reads locally. query_local(query,budget_ms) accepts only list/validated lookup and budgets1..5000, creates a local deadline, bounds Server :ref waits, checks Registry PID before/after and returns static errors. Loaded non-authorities answer not_authority; missing code/disconnected targets answer unavailable. Real Ref/PID/incarnation validation, descriptor replacement,128 identities and1MiB caps remain. Registry/Resources/Delegations/Agents retain one_for_all and Registry-loss invalidation.

Endpoint source and both registrations are removed. No new dependency, query supervisor, watchdog, quota service, retry or replay. Node.Agents aggregation logic is unchanged:32 trusted targets,8 concurrent requests, shared5s receive deadline, complete-envelope accounting and partial failures. Only its connection-contract documentation changed.

Approved semantics permit finite remote reads to start/finish after caller abandonment and OTP reconnection after the connected precheck. Initially disconnected targets reject. No300ms cleanup, instantaneous cancellation, expired-admission rejection, mailbox retraction or hard real-time guarantee is claimed.

## Historical validation results

Commands ran from repository root with low schedulers; test environment unless noted.

| Check / execution | Recorded outcome |
| --- | --- |
| Task context validate | exit0 |
| MIX_ENV=test mix compile --warnings-as-errors | exit0 after final production changes |
| mix format --check-formatted | exit0 |
| Focused Agent/Node/CLI/daemon | exit0;93 passed/18 excluded before final local additions |
| Final Agent suite | exit0;11 passed |
| Final ordinary mix test | exit0;194 passed/25 excluded |
| Named Node/CLI/daemon with distributed/resource included | exit0;101 passed: Node75,daemon7,CLI19 |
| Final named discovery/resource | exit0;9 passed;seed540523 |
| mix credo --strict | exit0;107 files,no issues |
| MIX_ENV=dev mix dialyzer | exit0;zero errors/skips;existing PLT,no forced refresh |
| git diff --check | exit0 |
| Owned named process audit | no owned coordinator/peer residuals |
| Post-review reader-PID assertion regression | exit0;1 passed/6 excluded;seed648055 |

Final ordinary194 comprises Actions35,Harness28,Runtime30,Agent11,Node60,daemon5,CLI18,Web7. Excluded distributed tests are not passing distributed evidence. The named host run preceded the final additional discovery assertions; final and independent nine-test discovery runs covered them. Counts are separate executions, not a sum of unique tests. Earlier192/193 full-suite outcomes were intermediate successes, not the final count.

## Failures and limitations retained in summary

- Initial named setup failed authentication: exit2,0/5 passed. Replaced environment-cookie launch with random cookie setup inside coordinator VM; later runs passed. Cookie values were not recorded.
- Initial Credo exited8 for three Discovery style/complexity issues; refactored validation checks, final strict gate passed.
- An early resource observer over-specified the queued code-server request shape: exit2,4/5 passed, observed0 instead of8. Corrected observation to code_call envelopes, retained finally/on_exit recovery; later actual resource runs observed8 in-flight requests and10 timeout failures under the shared deadline.
- MIX_ENV=test Dialyzer exited2 because web test support referenced missing ExUnit.Callbacks/CaseTemplate PLT functions. Test analysis is not claimed clean; dev analysis passed separately. No unrelated dependency/PLT configuration repair was made.
- Named disconnect/teardown generated OTP overlapping-partition warnings; host disk alarm notices also occurred. These were not rewritten as test failures. Successful and failed original logs were both removed under the user's cleanup request.
- Parent active LSP probe on Discovery,AuthoritySupervisor,Node,Node.Agents timed out on all4 files; inconclusive,none confirmed clean.
- Same-host observations do not establish physical-network/half-open/long-stress behavior. Matching library builds are required; no mixed-version fallback.

## Durable product regression coverage

Agent tests cover descriptors/real Ref attachment without input, ID reuse/stale descriptors, malformed IDs/budgets, credential marker exclusion,128-identity overflow, local timeout, actual execution kill with unchanged Registry/Agents PIDs and caller-loss retirement while Server remains suspended. Recovery returns the exact original Ref/snapshot. The post-review assertion pins the observed reader PID to the worker being killed.

Named Node tests cover same-name authorities, partial non-authority failures, remote identity replacement/restart, remote caller loss with worker alive then retired before Server resume, execution kill isolation, public timeout/late replies in a live caller, disconnect/finite remote completion through standard_io, initially disconnected rejection, OTP reconnect control, missing code, aggregate caller-loss cleanup and ten delayed loads with8 concurrent requests/one shared deadline. No product test switch or old research script is used.

Node envelope tests retain32-target and full1MiB accounting with failure reservation. All seven role combinations assert authority versus not_authority capability; Registry-loss lifecycle and CLI reattachment/daemon startup regressions passed.

## Reduction, contracts and final state

Discovery154 + Endpoint134 =288 source lines before; Discovery153 after:135 fewer lines,46.9%,2 modules→1. Main production diff net136 lines removed. No manifest/lockfile changes. Backend index/directory/orchestration specs describe final signatures/errors/budgets/isolation and OTP semantics; historical discovery task has supersession notes. README was restored externally to HEAD after review; detailed contracts remain in backend specs.

Independent review PASS is preserved separately. Acceptance-time hash comparison showed unchanged production/spec/Node test files and only the already-tested reader assertion change. Source-hash inventory is now deleted; this statement records that prior comparison. Cleanup itself did not change product code.

Historical Git observations differed by time: implementation/review saw an empty index; a later parent audit saw externally staged files and preserved them; acceptance/cleanup observed an empty index again. This session issued no staging/unstaging/commit/push commands. Old research summaries were updated for cleanup without rerunning experiments. AC1–AC7 are complete; task status/archives were not automatically changed.
