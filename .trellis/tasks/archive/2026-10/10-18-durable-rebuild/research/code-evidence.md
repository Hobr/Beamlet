# 规划代码证据

核查基线：dev，最新历史 39b85a2；工作区已有前序设计文档修改，不覆盖、不作为本代码任务产物。以下是当前实现差距，不是已实现的新保证。

- apps/beamlet_storage/lib/beamlet/storage/agent_records.ex:33：create/input/consume/fork/restore；fork_messages 和 insert_inherited 将消息复制。
- apps/beamlet_storage/lib/beamlet/storage/schema/checkpoint.ex:6：无 through_seq/reducer version，data 是正文状态。
- apps/beamlet_storage/lib/beamlet/storage/schema/operation.ex:6：已有 owner/turn/tool_call/ordinal，缺模型 step/来源契约。
- apps/beamlet_storage/lib/beamlet/storage/operation_records.ex:480：batch 预留 2*N seq；batch_member 返回 accept_seq，accept_history 使用预留槽。
- apps/beamlet_storage/lib/beamlet/storage/records.ex:148：advance_agent_history 与 Agent CAS 耦合，需将 Runtime 采纳移出 Agent 事件位置争用。
- apps/beamlet_runtime/lib/beamlet/runtime/persistence.ex:20：owner.expected_version/accept_seq；description 未固定全部新来源契约。
- apps/beamlet_agent/lib/beamlet/agent/durable.ex:90：model_persistence 无 owner；检查点含 messages/assistant。
- apps/beamlet_storage/lib/beamlet/storage/dataset.ex:192：format_version==1，初始化元数据写死1；需按 role 显式新格式，拒绝旧 authority。
- apps/beamlet_storage/test/support/contract_fixture.ex:45：PG 环境 BEAMLET_PG_SOCKET_DIR，可选 PORT/USER；真实双库契约不能跳过。
- scripts/deployment/durable-e2e.sh:18：实际宿主为 apps/beamlet_app_server，不是旧 beamlet_daemon 或 beamlet_server 目录。
- apps/beamlet_agent/lib/beamlet/agent/history.ex 与 trace_export.ex、Storage.History：按旧消息/检查点投影，需引用闭包。
- apps/beamlet_app_server/test/beamlet/durable_e2e_test.exs：两进程 reopen/restore/export/fork，需重写断言适配新数据；不是断电或物理跨主机证据。

外部 DeepSeek-Harness 仅使用已记录的用户思想摘要，不在本任务假设其未核验实现。新完整设计：docs/architecture/agent-operation-persistence.md；验收：docs/architecture/persistence-delivery.md。
