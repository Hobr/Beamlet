# 模型与设计文档

Beamlet 的设计以独立 Effect 的持久执行和恢复为中心。当前已完成有界 Quint 模型和首版实现契约，尚无 Runtime/Ecto 实现。

## 阅读顺序

1. [领域术语](../GLOSSARY.md)：Intent、Execution、Outcome 及各参与者的含义。
2. [核心边界与设计理由](rfc/0001-core-boundaries.md)：为什么采用这些边界，以及取舍带来的限制。
3. [首版范围](spec/first-release-scope.md)：首版闭环、交付边界和后置能力。
4. 按实现任务阅读下表中的 SPEC。
5. [Quint 模型](quint/README.md)：可执行入口、检查命令及验证边界。

## 规格索引

| 文档 | 回答的问题 |
| --- | --- |
| [核心状态机](spec/core-state-machines.md) | 尝试如何推进，什么证据可以终结 Intent，冲突如何阻塞判断？ |
| [Operation / Handler](spec/operation-handler-contracts.md) | 操作如何保持兼容，Handler 可以声明什么能力？ |
| [lease 与权限](spec/leases-and-permissions.md) | 领取、启动、续租、失效与结果资格有什么区别？ |
| [持久值与消息](spec/persistent-values-and-messages.md) | 值如何比较，提交及报告如何标识、去重与保存冲突？ |
| [原子存储命令](spec/storage-command-contracts.md) | 哪些事实必须同事务提交，两个 SQL 后端需要通过什么验收？ |
| [Handler 与恢复](spec/handler-recovery-contracts.md) | 如何保存能力快照、完成关联，以及验证安全重试和停止条件？ |
| [多 Intent 与 Tool Call](spec/multi-intent-and-tool-calls.md) | 多个 Agent 如何独立执行，调用方如何恢复多依赖结果收集？ |

RFC 解释设计理由；SPEC 规定行为与验收要求。核心状态机中的协调/治理章节保留未来约束，交付范围以首版范围文档为准。
持久值、存储命令和 Handler 恢复文档细化首版契约；物理 schema、公开 Elixir API 和具体 Adapter 仍需在实现中落实。
Quint 的整数身份、观察快照和有界参数只服务于模型检查，不直接规定产品编码或数据库字段。

## 验证资料

- [模型覆盖与边界](quint/coverage.md)：需求到场景/性质的映射、最近一次模型验收结果和未覆盖部分。
- [故意错误规则](quint/counterexamples.md)：76 条 mutation 的检查目标与复现方式。
- 运行日志和 ITF 由检查工具输出到临时目录或指定的 `--log-dir`，不纳入本目录。
