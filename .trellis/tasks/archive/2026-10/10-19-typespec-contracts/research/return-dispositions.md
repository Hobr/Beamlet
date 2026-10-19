# Return dispositions — Stage E

The baseline comprised68 warnings. Its raw logs, duplicate stage outputs and temporary probes were removed at the user's request before commit. The table retains each finding's original coordinates, actual call semantics and disposition; match by module/function/call after annotation shifts. This is not an assertion that every warning was a business defect.

Stage E started with **60 findings: 57 unmatched returns and3 dead-code findings**; some baseline/new results had already been disposed by owning layers. Final root `mix dialyzer` includes defaults, unknown and unmatched_returns and reports **0 errors, 0 skipped, 0 unnecessary skips**. An initial rerun still found the conditional late-evidence result; it was then explicitly reviewed and disposed before the passing run.

Each discard was checked against the owning clauses and worker reports. No affected-row assertion, acceptance/transaction error propagation, error tag, message, exception, retry policy or lifecycle deadline was changed. No ignore configuration, warning suppression or new application dependency was added.

## Retained baseline: all 68 findings

| ID | Retained coordinate | Return semantics and disposition |
| --- | --- | --- |
| B01 | `lib/beamlet/actions/storage/migrations/authority_v1.ex:31` | AuthorityV1.up: intermediate flush adapter results. DDL effects/raising unchanged; explicit discard. |
| B02 | `lib/beamlet/actions/storage/migrations/authority_v1.ex:18` | AuthorityV1.up: executions unique index descriptor. DDL effects/raising unchanged; explicit discard. |
| B03 | `lib/beamlet/actions/storage/migrations/authority_v1.ex:24` | AuthorityV1.up: evidence unique index descriptor. DDL effects/raising unchanged; explicit discard. |
| B04 | `lib/beamlet/actions/storage/migrations/authority_v1.ex:30` | AuthorityV1.up: event unique index descriptor. DDL effects/raising unchanged; explicit discard. |
| B05 | `lib/beamlet/actions/storage/migrations/journal_v1.ex:10` | JournalV1.up: authority/attempt unique index descriptor. DDL effects/raising unchanged; explicit discard. |
| B06 | `lib/beamlet/actions/storage/migrations/journal_v1.ex:11` | JournalV1.up: receipt ID unique index descriptor. DDL effects/raising unchanged; explicit discard. |
| B07 | `lib/beamlet/agent/storage/migrations/agent_v1.ex:36` | AgentV1.up: intermediate flush adapter results. Descriptor/list unused; effects/raising unchanged; explicit discard. |
| B08 | `lib/beamlet/agent/storage/migrations/agent_v1.ex:10` | AgentV1.up: agents alias index. Descriptor/list unused; effects/raising unchanged; explicit discard. |
| B09 | `lib/beamlet/agent/storage/migrations/agent_v1.ex:20` | AgentV1.up: events sequence index. Descriptor/list unused; effects/raising unchanged; explicit discard. |
| B10 | `lib/beamlet/agent/storage/migrations/agent_v1.ex:21` | AgentV1.up: events dedupe index. Descriptor/list unused; effects/raising unchanged; explicit discard. |
| B11 | `lib/beamlet/agent/storage/migrations/agent_v1.ex:27` | AgentV1.up: commands identity index. Descriptor/list unused; effects/raising unchanged; explicit discard. |
| B12 | `lib/beamlet/agent/storage/migrations/agent_v1.ex:28` | AgentV1.up: events turn index. Descriptor/list unused; effects/raising unchanged; explicit discard. |
| B13 | `lib/beamlet/agent/storage/migrations/agent_v1.ex:29` | AgentV1.up: checkpoint index. Descriptor/list unused; effects/raising unchanged; explicit discard. |
| B14 | `lib/beamlet/agent/storage/migrations/agent_v1.ex:35` | AgentV1.up: operation owner index. Descriptor/list unused; effects/raising unchanged; explicit discard. |
| B15 | `lib/beamlet/cli/runner.ex:13` | Runner locale installation returns locale string; installation is the effect; explicit discard (host worker). |
| B16 | `lib/beamlet/i18n/catalogue.ex:50` | Catalogue extraction `idle`; rendered string is unused; literal macro and extraction preserved. |
| B17 | `lib/beamlet/i18n/catalogue.ex:51` | Catalogue extraction `running`; rendered string is unused; literal macro and extraction preserved. |
| B18 | `lib/beamlet/i18n/catalogue.ex:52` | Catalogue extraction `waiting`; rendered string is unused; literal macro and extraction preserved. |
| B19 | `lib/beamlet/i18n/catalogue.ex:53` | Catalogue extraction `done`; rendered string is unused; literal macro and extraction preserved. |
| B20 | `lib/beamlet/i18n/catalogue.ex:54` | Catalogue extraction `stopped`; rendered string is unused; literal macro and extraction preserved. |
| B21 | `lib/beamlet/i18n/catalogue.ex:55` | Catalogue extraction `error`; rendered string is unused; literal macro and extraction preserved. |
| B22 | `lib/beamlet/i18n/catalogue.ex:56` | Catalogue extraction `starting`; rendered string is unused; literal macro and extraction preserved. |
| B23 | `lib/beamlet/i18n/catalogue.ex:57` | Catalogue extraction `completed`; rendered string is unused; literal macro and extraction preserved. |
| B24 | `lib/beamlet/i18n/catalogue.ex:58` | Catalogue extraction `pending`; rendered string is unused; literal macro and extraction preserved. |
| B25 | `lib/beamlet/i18n/catalogue.ex:59` | Catalogue extraction `admitting`; rendered string is unused; literal macro and extraction preserved. |
| B26 | `lib/beamlet/i18n/catalogue.ex:60` | Catalogue extraction `unknown`; rendered string is unused; literal macro and extraction preserved. |
| B27 | `lib/beamlet/i18n/catalogue.ex:61` | Catalogue extraction `complete`; rendered string is unused; literal macro and extraction preserved. |
| B28 | `lib/beamlet/i18n/catalogue.ex:62` | Catalogue extraction `partial`; rendered string is unused; literal macro and extraction preserved. |
| B29 | `lib/beamlet/i18n/catalogue.ex:63` | Catalogue extraction `ready`; rendered string is unused; literal macro and extraction preserved. |
| B30 | `lib/beamlet/i18n/catalogue.ex:64` | Catalogue extraction `active`; rendered string is unused; literal macro and extraction preserved. |
| B31 | `lib/beamlet/i18n/catalogue.ex:65` | Catalogue extraction `connected`; rendered string is unused; literal macro and extraction preserved. |
| B32 | `lib/beamlet/i18n/catalogue.ex:66` | Catalogue extraction `disconnected`; rendered string is unused; literal macro and extraction preserved. |
| B33 | `lib/beamlet/i18n/catalogue.ex:67` | Catalogue extraction `enabled`; rendered string is unused; literal macro and extraction preserved. |
| B34 | `lib/beamlet/i18n/catalogue.ex:68` | Catalogue extraction `disabled`; rendered string is unused; literal macro and extraction preserved. |
| B35 | `lib/beamlet/i18n/catalogue.ex:69` | Catalogue extraction `local`; rendered string is unused; literal macro and extraction preserved. |
| B36 | `lib/beamlet/i18n/catalogue.ex:75` | Catalogue extraction `invalid_command`; rendered string is unused; literal macro and extraction preserved. |
| B37 | `lib/beamlet/i18n/catalogue.ex:76` | Catalogue extraction `invalid_configuration`; rendered string is unused; literal macro and extraction preserved. |
| B38 | `lib/beamlet/i18n/catalogue.ex:77` | Catalogue extraction `invalid_authority`; rendered string is unused; literal macro and extraction preserved. |
| B39 | `lib/beamlet/i18n/catalogue.ex:78` | Catalogue extraction `alias_exists`; rendered string is unused; literal macro and extraction preserved. |
| B40 | `lib/beamlet/i18n/catalogue.ex:79` | Catalogue extraction `alias_limit`; rendered string is unused; literal macro and extraction preserved. |
| B41 | `lib/beamlet/i18n/catalogue.ex:80` | Catalogue extraction `invalid_alias`; rendered string is unused; literal macro and extraction preserved. |
| B42 | `lib/beamlet/i18n/catalogue.ex:81` | Catalogue extraction `unknown_alias`; rendered string is unused; literal macro and extraction preserved. |
| B43 | `lib/beamlet/i18n/catalogue.ex:82` | Catalogue extraction `not_found`; rendered string is unused; literal macro and extraction preserved. |
| B44 | `lib/beamlet/i18n/catalogue.ex:83` | Catalogue extraction `not_authority`; rendered string is unused; literal macro and extraction preserved. |
| B45 | `lib/beamlet/i18n/catalogue.ex:84` | Catalogue extraction `stale_agent`; rendered string is unused; literal macro and extraction preserved. |
| B46 | `lib/beamlet/i18n/catalogue.ex:85` | Catalogue extraction `unavailable`; rendered string is unused; literal macro and extraction preserved. |
| B47 | `lib/beamlet/i18n/catalogue.ex:86` | Catalogue extraction `timeout`; rendered string is unused; literal macro and extraction preserved. |
| B48 | `lib/beamlet/i18n/catalogue.ex:87` | Catalogue extraction `limit`; rendered string is unused; literal macro and extraction preserved. |
| B49 | `lib/beamlet/i18n/catalogue.ex:88` | Catalogue extraction `busy`; rendered string is unused; literal macro and extraction preserved. |
| B50 | `lib/beamlet/i18n/catalogue.ex:89` | Catalogue extraction `event_limit`; rendered string is unused; literal macro and extraction preserved. |
| B51 | `lib/beamlet/i18n/catalogue.ex:90` | Catalogue extraction `timeout_or_loss`; rendered string is unused; literal macro and extraction preserved. |
| B52 | `lib/beamlet/i18n/catalogue.ex:91` | Catalogue extraction `invalid_watch_options`; rendered string is unused; literal macro and extraction preserved. |
| B53 | `lib/beamlet/i18n/catalogue.ex:92` | Catalogue extraction `request_failed`; rendered string is unused; literal macro and extraction preserved. |
| B54 | `lib/beamlet/i18n/catalogue.ex:93` | Catalogue extraction `deadline`; rendered string is unused; literal macro and extraction preserved. |
| B55 | `lib/beamlet/i18n/catalogue.ex:94` | Catalogue extraction `invalid_draft`; rendered string is unused; literal macro and extraction preserved. |
| B56 | `lib/beamlet/i18n/catalogue.ex:95` | Catalogue extraction `configuration_unavailable`; rendered string is unused; literal macro and extraction preserved. |
| B57 | `lib/beamlet/i18n/catalogue.ex:96` | Catalogue extraction `create_unknown`; rendered string is unused; literal macro and extraction preserved. |
| B58 | `lib/beamlet/i18n/locale.ex:66` | Locale.put installs process locale; canonical value already bound and returned; discard setter result. |
| B59 | `lib/beamlet/runtime/directory.ex:185` | NodeEndpoint.init conditional Process.monitor reference/nil; DOWN is handled by gateway PID; discard reference, retain monitor. |
| B60 | `lib/beamlet/runtime/operation_coordinator.ex:175` | Coordinator late-completion evidence, best-effort after immutable accepted Result. Failure still reports admission failure; no retry or second completion. Discard whole conditional result. |
| B61 | `lib/beamlet/storage/migrations.ex:10` | install_metadata CREATE bang SQL result. Side effects required, result unused; exceptions and transaction wrapper retained. |
| B62 | `lib/beamlet/storage/migrations.ex:17` | install_metadata INSERT bang SQL result. Side effects required, result unused; exceptions and transaction wrapper retained. |
| B63 | `lib/beamlet/storage/migrations.ex:31` | install Migrator.run applied migration IDs. Side effects required, result unused; exceptions and transaction wrapper retained. |
| B64 | `lib/beamlet/storage/migrations.ex:32` | install metadata UPDATE bang SQL result. Side effects required, result unused; exceptions and transaction wrapper retained. |
| B65 | `lib/beamlet_web/live/workbench_live.ex:69` | open_handle launches owned async caller (PID) or returns :ok for nil; result handled asynchronously; explicit discard (host worker). |
| B66 | `lib/beamlet_web/locale.ex:36` | Locale plug/mount/params installs process locale; canonical locale already bound; explicit setter-result discard (host worker). |
| B67 | `lib/beamlet_web/locale.ex:87` | Locale plug/mount/params installs process locale; canonical locale already bound; explicit setter-result discard (host worker). |
| B68 | `lib/beamlet_web/locale.ex:105` | Locale plug/mount/params installs process locale; canonical locale already bound; explicit setter-result discard (host worker). |

## Additional findings exposed by later contracts

These nine unmatched returns were absent from the retained baseline. Host work already handled N9; N1–N8 were present at Stage E entry.

| ID | Function/call | Return semantics and disposition |
| --- | --- | --- |
| N1 | Delegation.await/7 → Agent.ack/2 | Best-effort subscriber credit; current snapshot and monitor processing owns completion. Explicit discard, no success inference. |
| N2 | Delegation.finish/7 → cleanup/1 | Final close command can fail on an expired reference; forward the already selected result as before. Explicit discard. |
| N3 | Delegation.cleanup/1 → stop_turn/1 | Best-effort retirement; still attempt unsubscribe and close. Explicit discard, no confirmed-stop claim. |
| N4 | Delegation.cleanup/1 → unsubscribe/2 | Best-effort cleanup of live subscription; still close. Explicit discard. |
| N5 | OperationOwner.await/1 → Runtime.ack/2 | Best-effort credit for possibly expired live Ref; controller continues lifecycle ownership. Explicit discard. |
| N6 | Server.do_fail/2 → stop_owned/1 | Sends stop to child/owner PIDs and returns unchanged state. Only effects needed before failure projection; explicit discard. |
| N7 | Coordinator.handle_call cancellation → cleanup/1 | No execution returns :ok, otherwise send returns cancel tuple. Neither is observed termination. Explicit discard, timers/classification retained. |
| N8 | Coordinator.finish/3 → cleanup/1 | Same cancellation-send effect; classification/acceptance retained. Explicit discard. |
| N9 | Web.OwnedCall sink → Agent.ack/2 | Display credit is best-effort, while source/owner DOWN drives sink lifecycle. Explicit discard by host worker. |

## Dead-code proof and inventory change

1. Durable.decide/2 receives `:ok | {:error, reason}` from both validate_decision/3 and resumable/3. validate_decision delegates only to execution_gate/1 (ok/error), validate_resolution/3 (ok/error), or a reduction over those values. resumable reduces from :ok and halts with an error tuple on every failed lookup/predicate. Neither returns false. Remove only the unreachable `else false` alternative; all real errors still pass through unchanged.
2. Server.start_children/3 has exactly one caller, control's validated delegate branch. Its reduce_while starts with `{:ok, %{}}`; start_delegation/6 has exactly one clause, performs spawn_monitor and returns `{:cont, {:ok, updated_children}}`. Any spawn error raises before a tuple is returned. Thus the reducer always returns `{:ok, children}` normally. Replace the case with that exact match and accept_delegation call; remove its impossible error arm. No spawn/monitor/send/state-update order changes for any possible execution.
3. Server.helper_monitors/1 had exactly one caller, that impossible arm. Remove its definition and spec. The real accept_delegation path retains its own helpers map construction.

Production identities decrease **1346 → 1345** (Agent **323 → 322**, private **772 → 771**) solely because of the unreachable helper removal. No normal private function is exempted. Regenerate the complete inventory with `elixir scripts/quality/check-contracts.exs --inventory`. The AST audit compared all148 sources with the base commit after stripping annotations, normalizing explicit discards/alias placement and allowing only the two documented dead-branch rewrites; no other difference was found. The first audit omitted callback attributes and failed; corrected normalization passed. Catalogue comparison removed only source-reference lines and confirmed unchanged msgids/translations/metadata. Generated audit/inventory files were removed during cleanup.

## Type correction and behavior findings

Caller.profile environment now accepts the actual open bounded placement data accepted by Operation.new/1, rather than incorrectly requiring binary/nil. This changes only a type declaration. No actual business behavior defect was established in Stage E. No business fix, schema migration, protocol/API change, test assertion change or new CI was performed.

## Verification boundary

Final umbrella, named distributed, PostgreSQL, E2E, existing/fresh project PLT results and LSP limitations are recorded in [final-verification.md](final-verification.md). Intermediate logs were removed during user-requested cleanup. The final report distinguishes executed successes from historical failed attempts and identifies the core-cache reuse.
