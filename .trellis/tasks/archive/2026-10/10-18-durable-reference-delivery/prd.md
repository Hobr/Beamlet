# D：引用式 fork、历史导出与产品验收

## Goal

交付已确认 durable 设计的本阶段代码，使 Storage/Agent fork、History/TraceExport、Server Host、CLI/Web 既有调用与展示、部署示例和端到端测试。

## Dependencies

必须等待 A、B、C 的契约与局部验收通过；最后交付父任务 AC1–AC7。 父任务为 [durable-rebuild](../10-18-durable-rebuild/prd.md)；子任务未完成不等于产品可发布。

## Requirements

- R1：同权威 fork 直接继承不可变引用清单，来源事实保留，无父事件链递归/新执行实体或正文 transcript。
- R2：新 Agent paused/await_input，不继承 pending/命令去重/消费/provider session；共享环境未确认停止默认禁执行，显式风险接受留痕。
- R3：历史与导出固定高水位，遍历输入/Operation/Result/artifact 闭包，区分 performed/inherited、缺失/脱敏；只读不需要 provider 在线。
- R4：产品接线使用新格式/契约，Server/CLI/Web 既有功能继续可用；提供因果与上下文来源可查询数据，不新增图 UI。
- R5：更新源码 spec/README/部署操作为实际实现；新格式显式初始化，真实数据库不删除，旧数据只拒绝不偷偷转换。

## Acceptance Criteria

- [x] AC1：父 Agent 不运行时新 Agent 可按直接内容引用恢复；旧结果不推进新 Agent、继承 usage 不算新费用。
- [x] AC2：并发导出不漂移，所有引用摘要可验证；缺内容明确阻塞，不把哈希当正文。
- [x] AC3：两独立 OS 进程 durable-e2e、named peer 故障窗口与调用计数、本地/分布式×内存/durable 覆盖。
- [x] AC4：全伞、严格静态、catalogue drift、backend build、受影响 copied/named release 和真实双库通过并记录；缺前提不记通过。

## Out of Scope

旧格式/API 兼容、删除已有数据、通用调度/Workflow/Branch/GC、自动重试/切主、图 UI、全部摘要/检索策略。只做本阶段及必要适配，不顺带修改前序设计文档的未提交内容。API/schema 允许破坏性变更，但不能降低 accepted/unknown/不重放保证。
