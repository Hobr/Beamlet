# 架构与规格

Beamlet 是 Effect Engine 的名称, 以独立 Effect 的持久执行和恢复为核心.
Beamlet!!!!! 是基于它的 Agent 框架及其系列产品的名称, 五个感叹号是名称的一部分.
本目录主要描述 Beamlet 引擎及其与上层调用方的边界, 不将 Beamlet!!!!! 的完整 Agent 恢复纳入引擎职责.
命名与规划中的组件见 [README](../README.md). RFC 解释设计取舍, SPEC 规定行为与验收要求.
本目录保留架构规格与可执行模型. [领域核心](../apps/beamlet/README.md) 已实现受限值, 执行状态机,
安全替代/RetryOnce 规则与独立报告来源. [SQLite Storage](../apps/beamlet_runtime/README.md) 已接入真实事务与重启恢复,
本地 Coordinator/Scheduler/Worker、同步 Echo 与独立资源库的持久审批示例已贯通;
[调用方 Caller](../apps/beamlet_agent/README.md) 已接入独立持久清单、slot 关联、await-all 结果汇总与单步持久决定/Continuation。
远端 Transport、第三方 Provider Adapter、PostgreSQL 与完整 Agent loop 尚待验收.
[模型与实现对照](implementation-conformance.md) 记录对应范围、修正与验证边界.

## 从这里开始

- [整体架构](spec/runtime-architecture.md): 组件, 部署和故障边界.
- [领域术语](../GLOSSARY.md): Intent, Execution, Outcome 与参与者.
- [核心设计理由](rfc/0001-core-boundaries.md) 与 [方案对照](rfc/0002-runtime-tradeoffs.md): 动机, 替代方案和研究依据.
- [首版范围](spec/first-release-scope.md) 与 [实现路线](spec/implementation-roadmap.md): 交付边界, 依赖顺序和实现前选择.

## 按问题查阅规格

| 文档 | 回答的问题 |
| --- | --- |
| [核心状态机](spec/core-state-machines.md) | 尝试如何推进, 什么证据可以终结 Intent, History 如何解释变化? |
| [Operation / Handler 与恢复](spec/operation-handler-contracts.md) | 如何定义兼容操作, 绑定资源, 保存能力与完成关联, 安全重试与停止? |
| [lease 与权限](spec/leases-and-permissions.md) | 领取, 启动, 续租, 失效与结果资格有什么区别? |
| [持久值与消息](spec/persistent-values-and-messages.md) | 值如何比较, 提交及报告如何标识, 去重与保存冲突? |
| [原子存储命令](spec/storage-command-contracts.md) | 哪些事实必须同事务提交, 两个 SQL 后端需要通过什么验收? |
| [多 Intent 与 Tool Call](spec/multi-intent-and-tool-calls.md) | 多个 Agent 如何独立执行, 调用方如何恢复多依赖结果与后续决策? |

## 运行模型检查

[Quint 检查指南](quint/README.md) 包含模型入口, 运行命令, 反例复现与验证边界.
模型源码, 场景及 mutation 是可执行验证资产, 按需要查阅; 阅读架构不要求逐个阅读它们.
