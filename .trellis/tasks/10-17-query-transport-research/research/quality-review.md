# Independent research quality review — historical PASS

## Retention status

On 2026-10-17 the user accepted the subsequent simplify-agent-queries implementation. Under the agreed cleanup scope, this research task's results/, experiments/ and dedicated .gitignore were removed. Raw records, scripts, source snapshots, failed-attempt logs and detailed command records are no longer distributed. This document preserves the independent review summary; it is not a substitute for available raw evidence or a runnable reproduction guide. Official sources remain in [report.md](report.md), [otp-paths.md](otp-paths.md) and [ecosystem.md](ecosystem.md).

## Historical verdict and scope

**PASS for the research deliverable**, reviewed on baseline9657d2a. This was not product-migration approval. At that time the Endpoint-to-Agent failure coupling was observed and reported, not repaired. Subsequent implementation has now been accepted separately; see [implementation acceptance](../../archive/2026-10/10-17-simplify-agent-queries/acceptance.md).

The independent reviewer read the curated context, plans, four research documents, four experiment scripts, original raw run/source snapshots and retained failures. It made exactly one independent full replay, generated a new summary and audited identities, events, connection observations, cleanup pairing and scope. No source/product/dependency/spec changes, commit or archive occurred in that research review.

## Historical execution summary

| Item | Recorded outcome |
| --- | --- |
| Original final run | 20261017T122252-5c3d06fc;98 scenarios/98 peer cleanups;205 rows;final passed |
| Independent full replay | 20261017T124152-6fd7b540;98 scenarios/98 peer cleanups;205 rows;final passed |
| Runtime | OTP29.1.2 / ERTS17.1.1 / Elixir1.20.4;MIX_ENV=test;two schedulers |
| Warning-fatal compile | exit0;718ms |
| Independent experiment | exit0;125814ms |
| New summary and semantic audit | exit0;no connection-classification differences from original run |
| Explicit experiment formatting / whitespace / syntax / scope checks | exit0;JSON/JSONL and Python checks passed |
| Scope at review time | HEAD9657d2a;index empty;research task only;no staged/committed evidence |

Each replay included32 critical groups ×3 new peers, one control and one96-query batch. The96 calls are within one scenario, not96 extra peers. Historical Discovery9 passed/seed631927 was a separate earlier product test run and was not rerun by this reviewer. Raw/summary/command files supporting this table have now been deleted as requested; the table is a historical record.

## Findings and interpretation preserved

- Modern rpc.call delegated to erpc in installed OTP29.1.2; both worked with rex suspended. The rex queue experiment used a version-locked internal protocol, not the recommended public API.
- Local timeout/caller death did not cancel650/900ms finite remote work: remote completion and actual DOWN were observed. Explicit remote kill was a separate control.
- Dead workers did not retract queued Server :ref messages. Alias/erpc response abandonment did not mean remote execution cancellation.
- The late-mailbox prose was corrected: sampling occurred1000ms after local return, typically only about470ms after650ms remote completion. Finite samples do not establish infinite-future absence.
- Connection observations used standard_io control and VM-local monitors/trace. Precheck/start/return barriers fixed ordering; positive reconnect controls came after observation windows. Earlier untraced nodeup senders remained unproven hypotheses.
- Actual Endpoint kill changed inner Registry/Resources/Agents/Endpoint PIDs and killed the old Agent; outer Node/AuthoritySupervisor stayed unchanged. Explicit recreation changed Agent PID/incarnation. This did not prove automatic business recovery or restart-intensity behavior.
- Community sources distinguished fixed tags from branch snapshots and official API facts from compatibility tests. No gen_rpc/Syn/Horde/libcluster installation or OTP29 compatibility certification occurred.
- Task-local ignore exceptions made raw evidence nonignored at research delivery time; this did not mean it had been committed. Those exceptions are now removed with the evidence directories.

## Historical cleanup and evidence limits

The independent replay recorded98 matched peer cleanups, empty residual command process groups, dead local callers/helpers, no owned peer OS/control survivors and stopped private epmd. Shared epmd was untouched. The coordinator's final mailbox contained one expected peer-stop nodedown notification; batch sampling had been empty. These are distinct observation windows.

Early tool/experiment failures were retained during research: Elixir startup, alias JSON encoding, overstrong send_safe assertions and an orchestration handoff interruption. The final replay passed; historical untraced failures did not establish a universal root cause. The failed-attempt originals have now also been cleaned rather than selectively retaining only favorable raw data.

No physical-host/production/half-open/loss/long-stress/instantaneous-cancellation/queue-retraction/restart-intensity proof was claimed. Full umbrella/static analysis/LSP were not run by this research reviewer. The subsequent product verification is documented independently and does not depend on deleted research scripts.

## Historical AC disposition

All six research criteria passed at review time: pinned execution paths, complete repeated scenario matrix, true failure-domain evidence, sourced ecosystem comparison, traceable deliverable and owned-process cleanup/scope. The original evidence was available then; after user-directed cleanup, the repository preserves conclusions, source citations and this review summary only. No current ability to replay or audit deleted raw records is asserted.
