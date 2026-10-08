# Beamlet 规范

本目录收录 Beamlet 的产品架构与运行时契约，包括通用 Elixir/OTP 持久化计算运行时、能力组合，以及构建于这些基础之上的 Agent 运行时。

## 阅读指南

从[架构索引](./architecture/index.md)开始，了解各项契约的归属与需求覆盖情况。

| 主题 | 文档 |
| --- | --- |
| 领域术语 | [术语表](./architecture/glossary.md) |
| 模块职责与依赖关系 | [逻辑边界](./architecture/boundaries.md) |
| 状态转换、公共 API 与记录 | [计算与 Effect](./architecture/computation-and-effects.md) |
| 持久化、执行尝试与故障恢复 | [权威存储与恢复](./architecture/authority-and-recovery.md) |
| 作用域能力、提供者与执行控制器 | [能力组合](./architecture/capability-composition.md) |
| 暂停、分支与可移植归档 | [生命周期与归档](./architecture/lifecycle-and-archives.md) |
| 终端角色、授权与可信节点 | [平台与信任](./architecture/platforms-and-trust.md) |
| 架构选择与替代方案 | [架构决策](./architecture/decisions.md) |
| 核心抽象与设计的可执行验证 | [Quint 核心模型](./quint/core/README.md) |
| 历史详细模型与补充验证证据 | [Quint 探索记录](./quint/README.md) |

## 规范状态

保留 `architecture-v1` 已评审目标基线，并补充待评审的执行主体、调用裁定、输入顺序与终态协议，选择理由见 [ADR-008](./architecture/decisions.md#adr-008)。这些内容尚不代表实现已经完成。候选存储方案、编解码限制和平台支持仍须满足各自明确列出的验证要求。

每份契约文档负责定义其接口、不变量、错误行为和必需的验证场景。架构决策说明选择理由与替代方案。修改行为时，应更新负责该行为的文档，并同步更新关联场景和索引条目。
