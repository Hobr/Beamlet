# A 阶段执行与交接板

授权：2026-10-18 用户批准 A 实施及依赖/隔离数据库测试设施。分支 feat/durable-storage，基线 a078aa3。其他阶段不启动。

## 拓扑与所有权

本阶段为 multi-seam：存储基础（Repo/codec/DDL）、记录事务（Agent/Operation/journal）及集成验证可分别测试。采用串行独占组件 writer → integration-only writer → fresh read-only reviewer，避免一个 writer 同时拥有全部主要合同。现有工作树含用户暂存的文档与任务，不能为了 managed worktree 清洁要求提交/重置它们；各 writer 在同一 checkout 严格串行，上一 writer 退出并留下持久交接后才转交，不并行写。

| 阶段 | cwd / 隔离策略 | 独占合同与可写范围 | Gate / 持久交接 |
| --- | --- | --- | --- |
| foundation | /mnt/data/Project/Beamlet-durable；串行独占 checkout | 新 Storage manifest、Repo/显式初始化与迁移、schemas、codec、artifact 基础、相应测试；根 mix.exs backend 白名单、mix.lock | 依赖解析/编译、基础 SQLite/codec 测试；托管输出 artifact 描述字段、函数、迁移和测试接口 |
| records | 同上，foundation 退出后接管 | AgentRecords/OperationRecords/ExecutorJournal 具体事务及对应契约测试；复用前阶段 Repo/codec/DDL，不扩 Runtime/Agent 业务 | 真实 SQLite 事务测试，文档化 B/C 可用的存储合同；跨组件必要变更先说明 |
| integration | 同上，records 退出后接管 | 只做组件拼接、隔离 PG 测试设施、整体验证/最小集成修复与 A 证据/现状 spec；不实现新的业务模块 | 两适配器、文件重启/竞争、普通/后端构建及全套适用检查；报告失败和未覆盖项 |
| review | 同 checkout，read-only | 审查本轮 Storage/构建差异，区分原有 staged 文档，不修改源码 | fresh correctness/security/spec 与证据核对，返回具体 findings 供父会话处置 |

所有 writer 先读 A manifests → PRD → design → implement 与本板；不得嵌套 subagents、激活下游、git add/commit/push/reset/stash 或更改用户索引。可准备本地隔离 PG，但不访问/修改未知现有数据库，不在 repo 保存密码。所有组件只产生存储事实，不启动 handler 或业务恢复。

基础/组件 handoff 通过 workflow 的持久 output artifact 传给下一阶段；若依赖、运行器或权限失败，报告并停止下游，不切换外部 CLI 代理或自动换模型。正常代码测试失败在本组件职责内修复并重测。最终集成/审核结果由父会话验收，不能由组件自行宣布整个 durable 已实现。
