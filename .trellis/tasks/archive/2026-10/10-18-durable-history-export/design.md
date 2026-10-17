# 持久历史查询与轨迹导出设计

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施；先决 A/B/C 已验收并提交（3aefa85、11577fb、f7be001）。

## 设计依据

- [主设计](../../../../../docs/architecture/agent-operation-persistence.md)
- [实施与验收计划](../../../../../docs/architecture/persistence-delivery.md)
- [术语](../../../../../GLOSSARY.md)

以上文档是契约来源；本文只收敛本任务范围，不另建相互竞争的设计。代码兼容性核对基线为 `a078aa3`，开工前重新核对后续变化。

## 归属与方案

主设计第 8、10–11 节及交付计划 D。history 使用当前约束及不可变事件视图，as_of/export 只从固定高水位内的不可变记录读取，messages 是事件视图而非第二份权威 transcript。格式为 manifest + JSONL events + checkpoints + artifacts，按 scope 保留原 seq/recorded_at，不伪造跨 Agent 全局顺序。默认不自动 GC，无需 pin/租约/后台调度器。

## Interface 与交接

Agent.history(locator, filters, cursor) 与有界流式 Agent.export(locator, scope, policy)；历史接口不返回活跃 PID，校验器不授予导入执行权限。D 用 fixture 验证继承数据，不依赖尚未实现的 E fork，避免循环依赖。

## 依赖与兼容

先决：[Agent 历史、检查点与暂停恢复](../10-18-durable-agent/prd.md) 验收通过后才能实施。

遵循[父设计](../../../10-18-agent-operation-persistence/design.md)的跨阶段契约、单权威部署与回退限制。具体源码位置开工前重新核对；这里只记录 seam 和职责，不以基线函数签名冻结未来实现细节。现有临时模式不能被持久失败静默接管。

## 验证边界

本阶段以自身 PRD 验收及交付计划对应阶段为准；保存实际测试命令、适配器/SQLite 引擎版本、故障切点和证据路径。未执行的故障模型必须明示，不能把相邻阶段或内存测试当作本阶段证据。
