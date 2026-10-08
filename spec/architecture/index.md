# 架构规范

状态：`architecture-v1` 为已评审历史基线；ADR-008 协议补充技术设计已评审并接受，见[技术处置](./protocol-review-2026-10-08.md#disposition)与[选择理由](./decisions.md#adr-008)。ADR-007 为条件候选；技术接受不表示完整形式检查、实现或运行时验证已经完成。

本规范指导通用 Elixir/OTP 运行时及其使用方。下文中的 API 表示法与载荷均为目标契约，不表示相关模块、存储后端或平台已经实现。

## 阅读顺序

| 文档 | 负责内容 |
| --- | --- |
| [术语表](./glossary.md) | 统一的领域语言 |
| [逻辑边界](./boundaries.md) | 逻辑模块、依赖方向、通用层与领域层的划分 |
| [计算与 Effect](./computation-and-effects.md) | 定义编写、标识、记录、公共 API 与回复投递 |
| [权威存储与恢复](./authority-and-recovery.md) | 原子命令、回执、纪元、执行尝试与故障 |
| [能力组合](./capability-composition.md) | Scope、代次、解析与外部执行编排 |
| [生命周期与归档](./lifecycle-and-archives.md) | 后续推进、暂停与恢复、稳定分支、ETF 与兼容性 |
| [平台与信任](./platforms-and-trust.md) | 终端角色、安全接入边界与可信成员前提 |
| [架构决策](./decisions.md) | 选择理由、替代方案与待完成的实现验证 |
| [协议补充评审记录](./protocol-review-2026-10-08.md) | 逐项技术处置、协议修订与剩余验证边界 |

修改契约前，先阅读负责该契约的文档，并遵循其“必需测试”部分。UI 使用方不得重复实现解码器、状态解释或授权策略。

## 需求与场景覆盖

需求与场景标识保持稳定。编号中的空缺是有意保留的；本索引覆盖运行时需求及其验证场景。场景标题前定义显式短锚点，链接不依赖完整标题的自动生成锚点。

| 需求 | 目标行为 | 场景 / 断言归属 |
| --- | --- | --- |
| R1 | 通用计算基础 | [S1](./boundaries.md#s1), [S6](./boundaries.md#s6) |
| R2 | Agent 使用能力，无需了解 Effect | [S1](./boundaries.md#s1), [S2](./computation-and-effects.md#s2) |
| R3 | 远程执行，并在计算宿主不可用时恢复 | [S3](./authority-and-recovery.md#s3) |
| R4 | 明确的生命周期、终态与定义故障语义 | [S5](./lifecycle-and-archives.md#s5) |
| R5 | CLI / TUI / 桌面 / Web / Android / 服务端节点目标 | [S15](./platforms-and-trust.md#s15) |
| R6 | 确认、故障与不确定性契约 | [S4](./authority-and-recovery.md#s4) |
| R8 | 显式、可恢复的状态推进与有序输入处置 | [S2](./computation-and-effects.md#s2) |
| R9 | 动态的作用域能力组合 | [S9](./capability-composition.md#s9) |
| R10 | 指定权威节点与集群持久性 | [S10](./authority-and-recovery.md#s10) |
| R11 | 按操作声明恢复、显式裁定与一次性重复执行许可 | [S11](./authority-and-recovery.md#s11) |
| R12 | 不可变意图与执行时提供者解析 | [S12](./capability-composition.md#s12) |
| R13 | 从稳定边界创建分支，后续工作具有独立标识 | [S13](./lifecycle-and-archives.md#s13) |
| R14 | 历史检查与外部执行前审核 | [S14](./capability-composition.md#s14) |
| R15 | BEAM 宿主上的可配置角色 | [S15](./platforms-and-trust.md#s15) |
| R16 | 运维方管理的可信集群 | [S16](./platforms-and-trust.md#s16) |
| R17 | 可移植归档，并导入为新分支 | [S17](./lifecycle-and-archives.md#s17) |
| R18 | 受限、版本化的 ETF 数据 | [S18](./lifecycle-and-archives.md#s18) |
| R19 | 暂停新工作，保留已获执行授权工作的结果 | [S19](./lifecycle-and-archives.md#s19) |

## 协议补充与验证场景

| 补充 | 主契约 | 必需场景 |
| --- | --- | --- |
| 执行主体绑定、重复分发与授权回执恢复 | [权威层](./authority-and-recovery.md) | [S4](./authority-and-recovery.md#s4)、[S12](./capability-composition.md#s12) |
| 观测分类、裁定竞态与一次性权限 | [调用裁定](./authority-and-recovery.md#invocation-resolution) | [S11](./authority-and-recovery.md#s11)、[S16](./platforms-and-trust.md#s16) |
| 统一输入顺序、通知去重与过期处置 | [计算契约](./computation-and-effects.md) | [S2](./computation-and-effects.md#s2) |
| finish 前置条件、FailRun 与终态结果保留 | [计算契约](./computation-and-effects.md) | [S2](./computation-and-effects.md#s2)、[S5](./lifecycle-and-archives.md#s5)、[S17](./lifecycle-and-archives.md#s17) |
| 新提案隔离与已提交授权保留 | [生命周期](./lifecycle-and-archives.md) | [S14](./capability-composition.md#s14)、[S19](./lifecycle-and-archives.md#s19) |

协议细化还覆盖[版本化失败声明](./capability-composition.md#failure-declaration)、[保留证据归约与恢复职责](./authority-and-recovery.md#3-契约)、failed 的长期审计及[接口前提验证义务](./boundaries.md#3-契约与数据流)。它们及原 ADR-008 补充的技术处置见[逐项评审](./protocol-review-2026-10-08.md#disposition)。形式模型仅验证对接口前提的使用，完整组合 depth10 仍无结论；运行时验证须覆盖对应模块与必需场景。

## 契约状态与版本管理

- **已评审目标**：架构基线接受的必需行为与不变量。
- **已评审补充**：具有单独记录的技术设计处置；不改写历史基线，不等于形式证明或运行时通过。
- **待评审补充**：尚未有逐项技术处置的新提案；不得通过其他补充的接受状态自动提升。
- **实现建议**：具体实现方案，必须通过其列出的可行性检查。
- **暂缓事项**：明确排除的工作或未来验证，不得暗示已经支持。

改变行为前，应更新负责该行为的契约与场景。保持需求和场景标识稳定。通过新增关联条目取代旧决策，保留原有理由。持久化格式独立于软件包发布进行版本管理；预发布标签不允许静默改变已保存历史的解释方式。

## 初始范围与实现验证

初始契约采用显式状态、不可变意图、逻辑标识、可信节点和稳定边界分支。范围不包括外部撤销 / Saga 补偿、恰好执行一次的保证、执行中分支、恶意成员隔离和内置审批流程。

初始实现最多使用一个权威组。Ra 是技术评审后的条件候选存储方案，须通过[架构决策](./decisions.md)中列出的工具链与持久化检查。编解码资源预算和真实设备 / 网络支持需要原型验证。

后续实现必须通过真实运行时测试满足各契约的断言矩阵。文档一致性检查本身不能证明可执行行为，也不能证明平台或后端支持。
