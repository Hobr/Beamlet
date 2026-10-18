# Agent 历史、检查点与暂停恢复

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施；先决阶段 A/B 已验收并提交（3aefa85、11577fb）。

## Goal

持久保存完整 Agent 业务历史与自足检查点，允许创建新的暂停实例并在显式决定后继续，避免重复派发或消费。

## 来源与依赖

父任务：[Agent / Operation 持久化与恢复](../../../10-18-agent-operation-persistence/prd.md)；来源需求：R1、R2、R4、R5、R8；对应交付阶段 C。

先决：[Runtime 权威记录与执行日志](../10-18-durable-runtime/prd.md) 验收通过后才能实施。

## Requirements

- C1：输入确认前提交，完整模型回复先落盘再验证全部 Tool 批次；非法批次零派发。
- C2：Tool 结果按原 ordinal 汇合，消费与上下文/检查点同事务提交，每 Agent/Operation/consumption_kind 消费一次。
- C3：restore 默认 paused，continue 显式校验版本、代次、配置依赖及未决风险；恢复加载数据而非执行旧 handler。
- C4：涉及外部效果的 uncertain/未确认停止/日志缺失默认阻塞，不直接作为普通 Tool failure 让模型再做一次。
- C5：可恢复定义保存配置/secret 引用，不保存凭据值或 provider session；Display/Observation 不作为历史或模型输入。

## Acceptance Criteria

- [x] 所有继续位置均验证 paused 恢复；消费前后/输入响应丢失/完整模型回复后崩溃不重复执行或消费。
- [x] 并发 Tool 反序完成仍按原序进入上下文；非法批次零派发，提交失败无部分批次。
- [x] 两个恢复请求与旧代迟到写只能激活一个实例；本地旧派发辅助进程必须退役，旧 Ref 不复活。
- [x] 缺失依赖、未知 schema、损坏 artifact 阻塞且零替代环境派发；secret 解析值不进历史/错误/导出。
- [x] display 条数、字段截断或全部省略不影响完整历史/检查点；恢复重建注解、不复制旧 reference/订阅。
- [x] 未决外部效果时零自动下一步模型/Tool 调用；显式解决后才推进。

## Scope Limits

只实现本阶段交付；不自动激活下游，不增加 Branch/Workflow/通用 replay 引擎，不提前声称整体 durable 可用。父任务所有安全约束及非目标继续适用。
