# 持久化发布与运维验收

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施；先决 A–E 已验收并提交（3aefa85、11577fb、f7be001、22d6159、c4b37fd）。

## Goal

在显式宿主和角色组合中可部署、迁移、备份与验证持久模式，存储失效时诚实停止准入，并形成端到端证据。

## 来源与依赖

父任务：[Agent / Operation 持久化与恢复](../10-18-agent-operation-persistence/prd.md)；来源需求：R1、R3、R4、R6、R7、R8；对应交付阶段 F。

先决：[持久数据契约与存储基础](../10-18-durable-storage/prd.md)、[Runtime 权威记录与执行日志](../10-18-durable-runtime/prd.md)、[Agent 历史、检查点与暂停恢复](../10-18-durable-agent/prd.md)、[持久历史查询与轨迹导出](../10-18-durable-history-export/prd.md)、[安全 fork 与恢复决定](../10-18-durable-fork-resolution/prd.md) 验收通过后才能实施。

## Requirements

- F1：CLI/daemon 显式配置存储；Repo 只由需要该存储的角色启动，interaction-only 不要求数据库。
- F2：迁移是独立运维动作；SQLite 必须本地持久卷/WAL/FULL，禁止网络文件系统 WAL。
- F3：注册 ready 与持久准入明确区分；进程存在但存储不可写时禁止受影响的新持久工作，无内存降级。
- F4：一致性备份可恢复到隔离部署；旧备份或 journal 丢失默认暂停并要求核对，不以记录缺失授权重执行。
- F5：以双适配器、真实文件/VM 故障及 release 场景记录实际保证，不把应用测试误称物理断电保障。

## Acceptance Criteria

- [x] 所有七种角色组合正确启动 authority/journal 所需 Repo；库加载及 interaction-only 不误启数据库，executor-only 不启动 Agent。
- [x] SQLite/PostgreSQL 跑同一存储契约与集成路径，迁移/格式不兼容安全拒绝；具体版本和 PRAGMA 有记录。
- [x] Repo/Node/Gateway 保持注册时断开数据库或注入磁盘满，输入/派发/worker 启动按角色受阻，历史只读可行时仍可用。
- [x] 一致性备份恢复至隔离 release，默认暂停核对；持久卷重启后可审阅、paused restore、显式继续、fork 和导出。
- [x] format、warning-fatal compile、针对性/完整测试、显式 named distributed suite、静态检查和受影响 release 验证均有证据与环境限制说明。

## Scope Limits

只实现本阶段交付；不自动激活下游，不增加 Branch/Workflow/通用 replay 引擎，不提前声称整体 durable 可用。父任务所有安全约束及非目标继续适用。
