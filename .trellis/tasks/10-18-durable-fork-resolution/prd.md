# 安全 fork 与恢复决定

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施；先决 A–D 已验收并提交（3aefa85、11577fb、f7be001、22d6159）。

## Goal

从安全检查点复制完整有效上下文创建独立新 Agent，并以显式决定处理迟到证据和共享环境风险，不撤销外部改变。

## 来源与依赖

父任务：[Agent / Operation 持久化与恢复](../10-18-agent-operation-persistence/prd.md)；来源需求：R4、R5、R6、R7、R8；对应交付阶段 E。

先决：[Agent 历史、检查点与暂停恢复](../10-18-durable-agent/prd.md)、[持久历史查询与轨迹导出](../10-18-durable-history-export/prd.md) 验收通过后才能实施。

## Requirements

- E1：fork 创建新 Agent 身份并保持 paused/await_input；原历史不变，旧 locator/Ref/别名不重定向。
- E2：只复制完整有效上下文、配置/Tool schema/摘要及来源；不继承执行实体、pending/join/消费、command 去重或取消/委派/peer 控制状态。
- E3：同权威原子复制并记录 command 响应，失败无部分 Agent，同 command 重试返回同 locator；超限拒绝不截断。
- E4：未确认可能改变共享环境的旧工作已停时，默认禁止新 Agent 执行；显式风险接受必须留痕。
- E5：迟到证据不覆盖旧 accepted Result，不自动污染新 Agent；回撤不撤销文件/API/费用等外部改变。

## Acceptance Criteria

- [x] 新 Agent 不读父 Agent 即可恢复；完整 Tool-call/result 配对及共享 artifact 引用有效，继承 usage 不重复计费。
- [x] 复制事务前后崩溃、相同 command 重试、超限、unsafe checkpoint 和版本冲突均无部分状态。
- [x] 源冻结后本地发送者退役、旧代写拒绝；远端未确认停止时新 Agent 保持阻塞，风险接受事件可审阅。
- [x] 不复制 Operation/Execution/evidence/运行控制/provider session/display 注解；原 Agent 迟到结果只补原历史。
- [x] 先 uncertain 后 success 经显式采纳只推进允许的上下文，不覆盖历史、不重复占用原 Tool result 槽。
- [x] 真实 fork 的历史/导出明确标记继承观察；源环境已发生改变在 fork 后仍存在。

## Scope Limits

只实现本阶段交付；不自动激活下游，不增加 Branch/Workflow/通用 replay 引擎，不提前声称整体 durable 可用。父任务所有安全约束及非目标继续适用。
