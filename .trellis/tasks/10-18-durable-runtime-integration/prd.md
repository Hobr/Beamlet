# B：Runtime 持久操作与并发结果采纳

## Goal

交付已确认 durable 设计的本阶段代码，使 Runtime.Persistence、submit/prepared、OperationCoordinator、ExecutorGateway/journal、Actions 需要的最小契约适配。

## Dependencies

必须等待 A 的新格式与事务契约验收；C 依赖本任务。 父任务为 [durable-rebuild](../10-18-durable-rebuild/prd.md)；子任务未完成不等于产品可发布。

## Requirements

- R1：移除 expected Agent accept_seq 协议；独立 Operation CAS 采纳结果，Agent 只经明确事件消费；模型/Tool 都支持 agent/turn/step 归属。
- R2：接收 A 的已准备 Operation/attempt，submit 不重复创建或改变确定请求；description 摘要固定来源和有效非敏感参数，临时凭据不持久。
- R3：保持 prepared/send_claimed、start_intent、terminal receipt、accepted-before-notify；本地与远端同一路径，双库非原子窗口显式。
- R4：迟到证据可保留，accepted Result 不覆盖；旧控制代不能发起新工作，证据查询/重传不能启动 Worker。
- R5：持久存储/日志失败阻止相关准入，不降级；保留 deadline/cancel 首触发 provenance 与真实终止分类。

## Acceptance Criteria

- [x] AC1：两个 sibling Operation 反序/并发完成均可独立采纳，无 Agent 版本争抢或事件预留空洞。
- [x] AC2：相同 admit/receipt 幂等不重复 Worker，claim 后断连和重启不重发；unknown/not_found 不被解读为未执行。
- [x] AC3：权威 accepted 内容 executor 离线仍能读；采纳写失败无正常 sink completion。
- [x] AC4：本地与 named peer 覆盖凭据不落库、完整 envelope 限制、取消/超时/成功竞争和准入故障。

## Out of Scope

旧格式/API 兼容、删除已有数据、通用调度/Workflow/Branch/GC、自动重试/切主、图 UI、全部摘要/检索策略。只做本阶段及必要适配，不顺带修改前序设计文档的未提交内容。API/schema 允许破坏性变更，但不能降低 accepted/unknown/不重放保证。
