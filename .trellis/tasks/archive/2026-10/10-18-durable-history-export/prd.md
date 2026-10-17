# 持久历史查询与轨迹导出

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施；先决 A/B/C 已验收并提交（3aefa85、11577fb、f7be001）。

## Goal

即使 Agent/Coordinator 不运行，也能查询完整业务历史并导出可验证的固定范围轨迹，支持审阅和离线分析。

## 来源与依赖

父任务：[Agent / Operation 持久化与恢复](../../../10-18-agent-operation-persistence/prd.md)；来源需求：R5、R6、R8；对应交付阶段 D。

先决：[Agent 历史、检查点与暂停恢复](../10-18-durable-agent/prd.md) 验收通过后才能实施。

## Requirements

- D1：通过持久 locator/turn/operation/cursor 查询，不依赖活进程或 Runtime retention。
- D2：区分当时事实、有效上下文和当前观察；区分继承上下文与本 Agent 执行。
- D3：导出固定各 scope 高水位，包含版本、digest、artifact 完整性、来源和缺失/脱敏标记；不用递归父历史拼接。
- D4：查询/导出有界，不执行历史代码，不采集私有思维链，不包含秘密解析值，不引入导出任务系统。

## Acceptance Criteria

- [x] Agent/Coordinator 退出且超过 retention 后仍能查询；display 截断不影响业务历史。
- [x] 导出期间追加事件不改变已固定范围，JSONL 可逐条验证，artifact digest 和缺失项明确。
- [x] 在预置合法继承上下文数据上验证来源路径未包含、外部关系未包含和继承 usage 不重复计费；E 落地后再验真实 fork 链路。
- [x] 长历史/慢导出受限内存、keyset 分页，不持有长期 SQLite 读事务；无凭据/活对象。
- [~] 导出包支持故障复盘、按 recorded_at 的本地耗时、路径比较及离线样本；usage/cost 不在持久契约内（部分满足），只读验证不等于可执行导入。

## Scope Limits

只实现本阶段交付；不自动激活下游，不增加 Branch/Workflow/通用 replay 引擎，不提前声称整体 durable 可用。父任务所有安全约束及非目标继续适用。
