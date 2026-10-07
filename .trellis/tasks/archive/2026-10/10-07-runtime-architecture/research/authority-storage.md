# Authority Storage Research

Date: 2026-10-07. Implementation research, not a runtime validation report.

## Required Contract

PRD R10 requires a canonical history per Run, durable acknowledgement, a designated authority subset, recovery after one authority node/disk loss under sufficient replica configuration, and no conflicting advancement during partitions. R19 orders suspension against step commits and attempt admission.

Storage must atomically validate conditional commands and retain application records for recovery, inspection, and archives. A local append-only file alone does not provide that protocol.

## Primary-source Findings

| Mechanism | Evidence | Relevance |
|---|---|---|
| OTP disk_log | [sync/1](https://www.erlang.org/doc/apps/kernel/disk_log.html#sync/1) distinguishes logging from disk write. | Local primitive, without a complete replicated command/ownership protocol. |
| Mnesia | [Transaction contexts](https://www.erlang.org/doc/apps/mnesia/mnesia_chap4.html) provide atomic updates and can retry transaction functions. [majority](https://www.erlang.org/doc/apps/mnesia/mnesia.html#change_table_majority/2) gates non-dirty updates. | A native alternative; external operations stay outside transactions. |
| Mnesia recovery | [System events](https://www.erlang.org/doc/apps/mnesia/mnesia_chap5.html#system-events) describe inconsistent_database and application recovery choices. | Majority alone is not the complete recovery procedure. |
| Ra | [Upstream](https://github.com/rabbitmq/ra) provides replicated state machines, leader election, snapshots and membership changes. | Fits the proposed closed-command authority model. |
| Ra API | [process_command/3](https://ra.hexdocs.pm/ra.html#process_command-3) returns after application and can time out without a majority. [consistent_query/2](https://ra.hexdocs.pm/ra.html#consistent_query-2) checks current leadership. | Committed receipts and consistent reads are needed for recovery/fork/export. |
| Ra persistence | [v3.2.0 WAL](https://raw.githubusercontent.com/rabbitmq/ra/v3.2.0/src/ra_log_wal.erl) synchronizes before written notifications and includes a no-sync path. | Verify the selected configuration and end-to-end acknowledgement; no-sync cannot support the promised profile. |
| Ra machine | [Machine contract](https://raw.githubusercontent.com/rabbitmq/ra/main/src/ra_machine.erl) applies entries on replicas and returns scheduling effects. | Keep command application deterministic; these scheduling effects are not Beamlet durable Effects. |

## Proposed First Implementation Target

Evaluate one Ra-backed authority group with three independently failing, persistent voting nodes for the single-node-loss profile. This is a concrete implementation proposal, not a new guarantee or a multi-backend framework.

The application machine handles closed data commands. It must not execute user computation callbacks or external operations. OTP services handle execution, discovery, supervision and reconciliation.

Keep public history/checkpoints as application records across backend snapshot/log compaction. The backend WAL is not the computation history or archive format.

## Version and Validation Gate

[Releases](https://github.com/rabbitmq/ra/releases) showed v3.2.0; its [README](https://raw.githubusercontent.com/rabbitmq/ra/v3.2.0/README.md) lists OTP 26/27. The project selects OTP 29/Elixir 1.20. OTP 29 compatibility is unverified. GitHub API access was rate-limited; upstream API/source browsing succeeded. No compile or fault test was run here.

Before adding a dependency in a future runtime implementation task:

1. Pin a candidate and verify the actual project toolchain.
2. Trace follower disk persistence, quorum commit, application reply and snapshot recovery.
3. Test receipt loss/retry, leader loss, permanent voter/disk loss, partitions/healing, stale ownership, and suspend/admission races.
4. Exclude replica-dependent clocks, randomness, runtime handles and ETF re-encoding from command application.
5. Reopen the dependency decision if a guarantee fails; do not weaken R10 or silently switch acknowledgement profiles.

The first runtime prototype owns this gate. The present task records a contract and recommendation without installing a backend.
