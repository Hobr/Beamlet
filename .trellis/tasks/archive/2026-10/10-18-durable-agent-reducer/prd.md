# C：Agent 事件归约、上下文与暂停恢复

## Goal

交付已确认 durable 设计的本阶段代码，使 Agent Server/Durable、事件 decoder/reducer、历史 loader、ContextBuilder、Integration、OperationOwner 与恢复/继续。

## Dependencies

必须等待 A、B 验收；D 依赖本任务。 父任务为 [durable-rebuild](../10-18-durable-rebuild/prd.md)；子任务未完成不等于产品可发布。

## Requirements

- R1：控制状态由版本化纯 reduce(state,event) 得到，不持久 messages/assistant 正文；只在提交后推进内存投影。
- R2：固定 through_seq 有界读取，校验连续事件/版本/摘要；checkpoint 为缓存，坏或缺失回退完整历史，坏历史/引用阻塞。
- R3：普通对话策略沿合法 input/Operation/accepted refs 构建逻辑请求与来源，来源归新 Operation；指令/策略/工具配置版本明确。
- R4：模型步骤与 Tool 批次原子准备后派发，完整回复从 accepted Result 读取；消费只记录引用，按 ordinal 汇合且幂等。
- R5：inspect 只读；restore 新 generation 且 paused，记录幂等中断并退役旧发送者；continue 只推进合法位置，claimed 未决不重发。
- R6：内存模式保留相同编排/上下文行为但不承诺持久恢复；保持订阅展示有界、Agent 控制响应及 helper 生命周期。

## Acceptance Criteria

- [x] AC1：活跃提交投影 == 全历史 reducer == checkpoint+后缀；replay 外部模型/Tool/网络调用为零。
- [x] AC2：原始输入接受后、模型准备前崩溃仍可读；准备/accept/consume 前后恢复无重复执行、重复消费。
- [x] AC3：相同来源与版本得到同一逻辑请求；后续配置/历史变化不修改已准备 Operation；未知证据不能自动进入上下文。
- [x] AC4：缺依赖只阻止执行不阻止只读历史；取消/不确定默认 blocker，旧回调/轮次/代际不推进新状态。
- [x] AC5：事件/恢复/构建边界和超限、长历史分页、helper 真正 DOWN 与既有 Agent/Node 并发回归通过。

## Out of Scope

旧格式/API 兼容、删除已有数据、通用调度/Workflow/Branch/GC、自动重试/切主、图 UI、全部摘要/检索策略。只做本阶段及必要适配，不顺带修改前序设计文档的未提交内容。API/schema 允许破坏性变更，但不能降低 accepted/unknown/不重放保证。
