# Runtime 权威记录与执行日志

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施：每阶段完成并提交后自动进入下一阶段；B–F 不再逐段请求确认。

## Goal

在 Runtime 的现有单 attempt 模型上持久记录派发、执行证据与一次终态接受，崩溃后不补跑 handler。

## 来源与依赖

父任务：[Agent / Operation 持久化与恢复](../../../10-18-agent-operation-persistence/prd.md)；来源需求：R1、R3、R4、R8；对应交付阶段 B。

先决：[持久数据契约与存储基础](../10-18-durable-storage/prd.md) 验收通过后才能实施。

## Requirements

- B1：发送前权威已提交 dispatch claim，启动 worker 前 executor 已提交 start_intent；durable completion 上报前已有本地终态。
- B2：send_claimed 后存在的投递不确定性只查询，不重发；not_found 和日志缺失不构成未执行证明。
- B3：每 Operation 接受一个 Result；重复 receipt 幂等，迟到冲突证据不覆盖已接受终态。
- B4：保留首个停止触发原因及实际终止观察，取消请求不改写 deadline/success；只读核对不产生新业务执行。

## Acceptance Criteria

- [x] 逐个崩溃切点验证持久 handler 调用计数不因重启/证据传输而增加；本地执行也走同一日志路径。
- [x] journal 写失败时零 worker 启动，终态写失败时不上报 durable completion；提交结果未知可按稳定 ID 核对。
- [x] 相同 receipt 重传返回同证据；不同 digest 冲突安全拒绝；终态接受只成功一次。
- [x] 竞争 deadline/cancel、kill escalation、无关崩溃、正常返回及迟到消息的分类与 e9bd6b4 一致；重启不由停止请求伪造已停。
- [x] Coordinator 终态未提交不通知 sink；进程仍注册但 DB/journal 不可写时相应持久准入被阻止。

## Scope Limits

只实现本阶段交付；不自动激活下游，不增加 Branch/Workflow/通用 replay 引擎，不提前声称整体 durable 可用。父任务所有安全约束及非目标继续适用。
