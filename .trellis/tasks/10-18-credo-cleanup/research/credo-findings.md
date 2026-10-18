# Credo findings at merge (9c6354d + dfa90cb)

Generated from `mix credo --strict --all --format=json` on the merged `dev`.
Summary: 106 findings - 58 AliasUsage (design, strict only), 22 Nesting,
5 CyclomaticComplexity, 4 WithClauses, 3 RedundantWithClauseResult,
3 AliasOrder, 3 CondStatements, 2 FunctionArity, 2 WithSingleClause,
1 UnlessWithElse, 1 PreferImplicitTry, 1 LongQuoteBlocks, 1 ModuleDoc.


## apps/beamlet_agent/lib/beamlet/agent.ex

- L67 [design/AliasUsage] Beamlet.Agent.restore: Nested modules could be aliased at the top of the invoking module.
- L73 [design/AliasUsage] Beamlet.Agent.inactive: Nested modules could be aliased at the top of the invoking module.
- L119 [design/AliasUsage] Beamlet.Agent.fork: Nested modules could be aliased at the top of the invoking module.
- L124 [design/AliasUsage] Beamlet.Agent.dormant_source: Nested modules could be aliased at the top of the invoking module.
- L145 [design/AliasUsage] Beamlet.Agent.history: Nested modules could be aliased at the top of the invoking module.
- L153 [design/AliasUsage] Beamlet.Agent.export: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_agent/lib/beamlet/agent/durable.ex

- L208 [refactor/WithClauses] Beamlet.Agent.Durable.record_reply: `with` doesn't end with a <- clause, move the non-pattern <- clauses inside the body of the `with`.
- L316 [refactor/WithClauses] Beamlet.Agent.Durable.consume_results: `with` doesn't end with a <- clause, move the non-pattern <- clauses inside the body of the `with`.
- L545 [design/AliasUsage] Beamlet.Agent.Durable.adopt_messages: Nested modules could be aliased at the top of the invoking module.
- L827 [refactor/FunctionArity] Beamlet.Agent.Durable.advance_raw: Function takes too many parameters (arity is 9, max is 8).
- L940 [refactor/RedundantWithClauseResult] Beamlet.Agent.Durable.dependencies: Last clause in `with` is redundant.
- L1028 [refactor/Nesting] Beamlet.Agent.Durable.pending_state: Function body is nested too deep (max depth is 2, was 3).
- L1252 [refactor/Nesting] Beamlet.Agent.Durable.consumptions: Function body is nested too deep (max depth is 2, was 3).
- L1321 [design/AliasUsage] Beamlet.Agent.Durable.fields: Nested modules could be aliased at the top of the invoking module.
- L1324 [design/AliasUsage] Beamlet.Agent.Durable.uuid: Nested modules could be aliased at the top of the invoking module.
- L1325 [design/AliasUsage] Beamlet.Agent.Durable.text: Nested modules could be aliased at the top of the invoking module.
- L1326 [design/AliasUsage] Beamlet.Agent.Durable.count: Nested modules could be aliased at the top of the invoking module.
- L1333 [design/AliasUsage] Beamlet.Agent.Durable.json: Nested modules could be aliased at the top of the invoking module.
- L1340 [design/AliasUsage] Beamlet.Agent.Durable.digest: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_agent/lib/beamlet/agent/history.ex

- L85 [refactor/WithClauses] Beamlet.Agent.History.dispatch: `with` doesn't end with a <- clause, move the non-pattern <- clauses inside the body of the `with`.
- L320 [design/AliasUsage] Beamlet.Agent.History.uuid: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_agent/lib/beamlet/agent/server.ex

- L97 [refactor/CyclomaticComplexity] Beamlet.Agent.Server.valid_keyword_options?: Function is too complex (cyclomatic complexity is 14, max is 9).
- L794 [refactor/Nesting] Beamlet.Agent.Server.complete_tool: Function body is nested too deep (max depth is 2, was 3).
- L1016 [refactor/UnlessWithElse] Beamlet.Agent.Server.durable_input: Unless conditions should avoid having an `else` block.

## apps/beamlet_agent/lib/beamlet/agent/trace_export.ex

- L22 [readability/AliasOrder] Beamlet.Agent.TraceExport: The alias `` is not alphabetically ordered among its group.
- L85 [refactor/Nesting] Beamlet.Agent.TraceExport.write: Function body is nested too deep (max depth is 2, was 4).
- L137 [design/AliasUsage] Beamlet.Agent.TraceExport.scope_id: Nested modules could be aliased at the top of the invoking module.
- L140 [design/AliasUsage] Beamlet.Agent.TraceExport.scope_id: Nested modules could be aliased at the top of the invoking module.
- L199 [refactor/Nesting] Beamlet.Agent.TraceExport.page: Function body is nested too deep (max depth is 2, was 3).
- L344 [refactor/Nesting] Beamlet.Agent.TraceExport.checkpoint_pages: Function body is nested too deep (max depth is 2, was 3).
- L423 [refactor/Nesting] Beamlet.Agent.TraceExport.copy_artifacts: Function body is nested too deep (max depth is 2, was 3).
- L637 [refactor/CyclomaticComplexity] Beamlet.Agent.TraceExport.manifest_shape: Function is too complex (cyclomatic complexity is 14, max is 9).
- L801 [refactor/Nesting] Beamlet.Agent.TraceExport.verify_artifacts: Function body is nested too deep (max depth is 2, was 3).

## apps/beamlet_agent/test/beamlet/durable_agent_test.exs

- L56 [design/AliasUsage] Beamlet.Agent.HeldTool.descriptor: Nested modules could be aliased at the top of the invoking module.
- L124 [design/AliasUsage] Beamlet.Agent.DurableAgentTest.providers: Nested modules could be aliased at the top of the invoking module.
- L175 [design/AliasUsage] Beamlet.Agent.DurableAgentTest.catalogue: Nested modules could be aliased at the top of the invoking module.
- L195 [design/AliasUsage] Beamlet.Agent.DurableAgentTest.boot_runtime: Nested modules could be aliased at the top of the invoking module.
- L240 [design/AliasUsage] Beamlet.Agent.DurableAgentTest.boot_runtime: Nested modules could be aliased at the top of the invoking module.
- L389 [design/AliasUsage] Beamlet.Agent.DurableAgentTest.batch: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_agent/test/beamlet/fork_test.exs

- L19 [readability/AliasOrder] Beamlet.Agent.ForkTest: The alias `` is not alphabetically ordered among its group.
- L132 [design/AliasUsage] Beamlet.Agent.ForkTest.complete_turn: Nested modules could be aliased at the top of the invoking module.
- L331 [design/AliasUsage] Beamlet.Agent.ForkTest: Nested modules could be aliased at the top of the invoking module.
- L513 [design/AliasUsage] Beamlet.Agent.ForkTest: Nested modules could be aliased at the top of the invoking module.
- L672 [design/AliasUsage] Beamlet.Agent.ForkTest: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_agent/test/beamlet/history_export_test.exs

- L82 [design/AliasUsage] Beamlet.Agent.HistoryExportTest.providers: Nested modules could be aliased at the top of the invoking module.
- L141 [design/AliasUsage] Beamlet.Agent.HistoryExportTest.input: Nested modules could be aliased at the top of the invoking module.
- L165 [design/AliasUsage] Beamlet.Agent.HistoryExportTest.reply: Nested modules could be aliased at the top of the invoking module.
- L209 [design/AliasUsage] Beamlet.Agent.HistoryExportTest.prepare_batch: Nested modules could be aliased at the top of the invoking module.
- L214 [design/AliasUsage] Beamlet.Agent.HistoryExportTest.prepare_batch: Nested modules could be aliased at the top of the invoking module.
- L626 [design/AliasUsage] Beamlet.Agent.HistoryExportTest: Nested modules could be aliased at the top of the invoking module.
- L753 [design/AliasUsage] Beamlet.Agent.HistoryExportTest.put_artifact!: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_daemon/lib/beamlet/daemon.ex

- L53 [design/AliasUsage] Beamlet.Daemon.storage: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_daemon/test/beamlet/durable_e2e_test.exs

- L46 [readability/AliasOrder] Beamlet.Daemon.DurableEndToEndTest: The alias `Beamlet.Storage.AgentRecords` is not alphabetically ordered among its group.
- L253 [design/AliasUsage] Beamlet.Daemon.DurableEndToEndTest.boot_wiring: Nested modules could be aliased at the top of the invoking module.
- L260 [design/AliasUsage] Beamlet.Daemon.DurableEndToEndTest.boot_wiring: Nested modules could be aliased at the top of the invoking module.
- L280 [design/AliasUsage] Beamlet.Daemon.DurableEndToEndTest.boot_wiring: Nested modules could be aliased at the top of the invoking module.
- L334 [design/AliasUsage] Beamlet.Daemon.DurableEndToEndTest.providers: Nested modules could be aliased at the top of the invoking module.
- L349 [design/AliasUsage] Beamlet.Daemon.DurableEndToEndTest.catalogue: Nested modules could be aliased at the top of the invoking module.
- L438 [design/AliasUsage] Beamlet.Daemon.DurableEndToEndTest.ready?: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_runtime/lib/beamlet/runtime.ex

- L100 [design/AliasUsage] Beamlet.Runtime.evidence: Nested modules could be aliased at the top of the invoking module.
- L102 [design/AliasUsage] Beamlet.Runtime.evidence: Nested modules could be aliased at the top of the invoking module.
- L132 [design/AliasUsage] Beamlet.Runtime.prepared: Nested modules could be aliased at the top of the invoking module.
- L133 [design/AliasUsage] Beamlet.Runtime.prepared: Nested modules could be aliased at the top of the invoking module.
- L153 [design/AliasUsage] Beamlet.Runtime.coordinators_available: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex

- L270 [refactor/FunctionArity] Beamlet.Runtime.ExecutorGateway.admission: Function takes too many parameters (arity is 9, max is 8).
- L313 [refactor/CondStatements] Beamlet.Runtime.ExecutorGateway.claim_start: Cond statements should contain at least two conditions besides `true`, consider using `if` instead.
- L347 [readability/WithSingleClause] Beamlet.Runtime.ExecutorGateway.digest_matches?: `with` contains only one <- clause and an `else` branch, consider using `case` instead
- L347 [refactor/WithClauses] Beamlet.Runtime.ExecutorGateway.digest_matches?: `with` doesn't start with a <- clause, move the non-pattern <- clauses outside of the `with`.
- L348 [design/AliasUsage] Beamlet.Runtime.ExecutorGateway.digest_matches?: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex

- L263 [design/AliasUsage] Beamlet.Runtime.OperationCoordinator.claim_dispatch: Nested modules could be aliased at the top of the invoking module.
- L347 [design/AliasUsage] Beamlet.Runtime.OperationCoordinator.persist_evidence: Nested modules could be aliased at the top of the invoking module.
- L390 [design/AliasUsage] Beamlet.Runtime.OperationCoordinator.persist_result: Nested modules could be aliased at the top of the invoking module.
- L400 [design/AliasUsage] Beamlet.Runtime.OperationCoordinator.admission: Nested modules could be aliased at the top of the invoking module.
- L408 [design/AliasUsage] Beamlet.Runtime.OperationCoordinator.admission_failure: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_runtime/lib/beamlet/runtime/persistence.ex

- L106 [design/AliasUsage] Beamlet.Runtime.Persistence.prepare: Nested modules could be aliased at the top of the invoking module.
- L119 [design/AliasUsage] Beamlet.Runtime.Persistence.admission_failure: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_storage/lib/beamlet/storage/admission.ex

- L148 [refactor/CondStatements] Beamlet.Storage.Admission.probe: Cond statements should contain at least two conditions besides `true`, consider using `if` instead.
- L162 [refactor/Nesting] Beamlet.Storage.Admission.write_probe: Function body is nested too deep (max depth is 2, was 3).

## apps/beamlet_storage/lib/beamlet/storage/agent_records.ex

- L107 [refactor/Nesting] Beamlet.Storage.AgentRecords.fetch: Function body is nested too deep (max depth is 2, was 3).
- L1096 [readability/WithSingleClause] Beamlet.Storage.AgentRecords.adoption_owner: `with` contains only one <- clause and an `else` branch, consider using `case` instead

## apps/beamlet_storage/lib/beamlet/storage/executor_journal.ex

- L56 [refactor/Nesting] Beamlet.Storage.ExecutorJournal.fetch: Function body is nested too deep (max depth is 2, was 3).
- L180 [refactor/CyclomaticComplexity] Beamlet.Storage.ExecutorJournal.write_stop: Function is too complex (cyclomatic complexity is 10, max is 9).
- L306 [refactor/Nesting] Beamlet.Storage.ExecutorJournal.write_terminal: Function body is nested too deep (max depth is 2, was 3).

## apps/beamlet_storage/lib/beamlet/storage/history.ex

- L47 [refactor/Nesting] Beamlet.Storage.History.event: Function body is nested too deep (max depth is 2, was 3).
- L147 [refactor/Nesting] Beamlet.Storage.History.operation: Function body is nested too deep (max depth is 2, was 3).
- L275 [refactor/CyclomaticComplexity] Beamlet.Storage.History.read_events: Function is too complex (cyclomatic complexity is 13, max is 9).
- L347 [refactor/CondStatements] Beamlet.Storage.History.take_rows: Cond statements should contain at least two conditions besides `true`, consider using `if` instead.

## apps/beamlet_storage/lib/beamlet/storage/host.ex

- L184 [refactor/Nesting] Beamlet.Storage.Host.open: Function body is nested too deep (max depth is 2, was 3).

## apps/beamlet_storage/lib/beamlet/storage/operation_records.ex

- L44 [design/AliasUsage] Beamlet.Storage.OperationRecords.fetch: Nested modules could be aliased at the top of the invoking module.
- L45 [refactor/Nesting] Beamlet.Storage.OperationRecords.fetch: Function body is nested too deep (max depth is 2, was 3).
- L102 [refactor/CyclomaticComplexity] Beamlet.Storage.OperationRecords.description: Function is too complex (cyclomatic complexity is 11, max is 9).
- L120 [refactor/RedundantWithClauseResult] Beamlet.Storage.OperationRecords.description: Last clause in `with` is redundant.
- L333 [refactor/Nesting] Beamlet.Storage.OperationRecords.batch_operations: Function body is nested too deep (max depth is 2, was 3).
- L637 [refactor/Nesting] Beamlet.Storage.OperationRecords.write_evidence: Function body is nested too deep (max depth is 2, was 3).
- L772 [refactor/Nesting] Beamlet.Storage.OperationRecords.do_accept: Function body is nested too deep (max depth is 2, was 3).
- L812 [refactor/Nesting] Beamlet.Storage.OperationRecords.accept_history: Function body is nested too deep (max depth is 2, was 3).

## apps/beamlet_storage/lib/beamlet/storage/terminal_artifacts.ex

- L45 [refactor/RedundantWithClauseResult] Beamlet.Storage.TerminalArtifacts.content: Last clause in `with` is redundant.
- L91 [refactor/Nesting] Beamlet.Storage.TerminalArtifacts.decode_item: Function body is nested too deep (max depth is 2, was 3).

## apps/beamlet_storage/lib/mix/tasks/beamlet.storage.migrate.ex

- L38 [design/AliasUsage] Mix.Tasks.Beamlet.Storage.Migrate.run: Nested modules could be aliased at the top of the invoking module.

## apps/beamlet_storage/test/beamlet/storage/storage_contract_test.exs

- L12 [refactor/LongQuoteBlocks] Beamlet.Storage.ContractSuite.__using__: Avoid long quote blocks.
- L52 [readability/PreferImplicitTry] Beamlet.Storage.ContractSuite.__using__: Prefer using an implicit `try` rather than explicit `try`.

## apps/beamlet_storage/test/support/contract_fixture.ex

- L158 [refactor/Nesting] Beamlet.Storage.ContractFixture.settings: Function body is nested too deep (max depth is 2, was 3).
- L203 [design/AliasUsage] Beamlet.Storage.ContractFixture.reject_downgraded: Nested modules could be aliased at the top of the invoking module.
- L223 [design/AliasUsage] Beamlet.Storage.ContractFixture.driver_failure: Nested modules could be aliased at the top of the invoking module.
- L231 [readability/ModuleDoc] Beamlet.Storage.ContractFixture.driver_failure: Modules should have a @moduledoc tag.
- L237 [design/AliasUsage] Beamlet.Storage.ContractFixture.driver_failure: Nested modules could be aliased at the top of the invoking module.
