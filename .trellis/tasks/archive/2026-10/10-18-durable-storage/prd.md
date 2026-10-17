# 持久数据契约与存储基础

状态：in_progress。用户于 2026-10-18 批准 A 阶段实施，包括添加已评审依赖与准备隔离数据库测试设施；B–F 未获开工授权。当前分支 feat/durable-storage。

## Goal

建立不依赖活进程的持久数据契约，以及 SQLite 默认、PostgreSQL 可选的权威存储和 executor SQLite 日志基础。

## 来源与依赖

父任务：[Agent / Operation 持久化与恢复](../../../10-18-agent-operation-persistence/prd.md)；来源需求：R1、R2、R3、R8；对应交付阶段 A。

先决：无上游实现任务；本子任务已获用户评审批准。

## Requirements

- A1：使用 Ecto；权威数据集是唯一业务事实源，executor 日志只保存执行证据。
- A2：只接受严格可版本化数据；拒绝嵌套 PID/reference/闭包/任意 struct、非法 UTF-8、越界内容及结构化凭据值；文本内容另受明确政策保护，不承诺自动识别任意秘密。
- A3：稳定 ID、版本 CAS、command 幂等、历史序号、artifact 引用和跨表业务转换具有明确的原子性。
- A4：库加载不启动 Repo/角色，不创建数据库文件，不自动迁移；临时模式仍可用，但持久失败不降级。
- A5：新应用可被普通及后端白名单构建发现；直接依赖由本应用声明，持久 JSON 与现有 wire/context 协议分别限额，不隐式截断。

## Acceptance Criteria

- [x] 两种实际权威数据库通过同一存储契约；独立 SQLite 文件验证 journal 事务。（两库各 10 个共享用例 + 3 个关闭/拒绝场景，双库共 64 用例通过；journal 仅 SQLite）
- [x] Ecto.Multi 任一步失败无部分事实；同 command 同参数返回原响应，不同参数冲突；CAS 竞争仅一方成功。
- [x] 非法活对象、深度/大小越界、未知 schema 字段及凭据形态键被所有写入口拒绝；artifact 引用同事务验证。
- [x] 普通/后端模式均能编译 Storage，库加载无 Repo/文件副作用；不依赖根工具或兄弟应用的传递依赖。
- [x] 稳定编码/digest、错误分类、限额/分页、单连接以外的 SQLite 竞争及提交结果未知有可复现测试。
- [x] authority/journal 迁移独立，旧代码拒绝较新格式；核对 WAL、FULL、foreign_keys 实际值，busy_timeout 按 Exqlite NIF 处理器语义核实。

验收证据见 [research/a-verification.md](./research/a-verification.md)（父会话实跑，取代 integration-evidence 的旧缺口描述）与 [research/integration-evidence.md](./research/integration-evidence.md)（集成过程记录）。cred 键拒绝为启发式而非秘密扫描器；PostgreSQL 仍为配置与场景验证，不是物理耐久性证明。

## Scope Limits

只实现本阶段交付；不自动激活下游，不增加 Branch/Workflow/通用 replay 引擎，不提前声称整体 durable 可用。父任务所有安全约束及非目标继续适用。
