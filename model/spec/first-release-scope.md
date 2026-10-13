# 首版范围

首版完成独立 Effect 的持久提交, 执行, 结果接受与恢复. 无法安全解决的 Unknown, 冲突或旧成功阻塞可以保持 Open,
并提供持久事实读取. 首版暂不提供人工协调裁定接口; 合法新证据和显式取消仍按核心守卫处理.

## 执行闭环

以下为目标交付行为, 不是当前已实现能力清单. 现有模型证据与后续工程验收分别列于文末.

提交 Effect → 持久建立 Intent/Execution → 派发给 Worker 并持久授权 → 在事务外执行 → 保存并验证报告 →
接受唯一 Outcome, 或保留等待/不确定事实 → 重启后重新发现工作或读取既有结果.

不同 Intent 可以并发, 不要求所有 Intent 自动终结. Agent 上下文, 业务等待集合和依赖清单由调用方持久保存.
多个 Agent 独立提交, 以及单轮 Tool Call 等待多个 Intent 的责任边界见
[多 Intent 与 Tool Call 契约](multi-intent-and-tool-calls.md).

| 能力 | 首版行为 | 主要规格 |
| --- | --- | --- |
| IEO 与提交身份 | 不可变操作定义, 稳定提交身份, Open/Closed, 唯一不可变 Outcome; 同身份冲突不覆盖定义 | [值与消息](persistent-values-and-messages.md) |
| 分布式启动 | 每个 Intent 一个逻辑 Authority; Worker incarnation/generation, lease, 先持久授权再调用 | [lease 与权限](leases-and-permissions.md) |
| 报告与判断 | 验证来源, 保存及去重, 持久后确认; 保留迟到证据与冲突 | [核心状态机](core-state-machines.md) |
| 等待与恢复 | Handler 支持时登记 durable Pending; 完成不依赖原 Worker 常驻; 通知丢失不丢工作 | [Handler 与恢复](operation-handler-contracts.md) |
| 安全替代 | 未授权 Prepared 可在旧领取失效后重领; 已授权尝试再次执行须有独立安全依据 | [存储命令](storage-command-contracts.md) |
| 终结 | 合格结果与 History 原子提交; Closed 不再新建尝试或授权; 取消不承诺外部停止/回滚 | [核心状态机](core-state-machines.md) |
| 持久存储 | 正式支持 Ecto SQLite/PostgreSQL; 真实事务保障一致性 | [后端符合性要求](storage-command-contracts.md) |

运行中控制修改, 完整策略治理和通用调度框架不属于首版契约. 最小停止/重试策略见 Handler 与恢复文档.
不提供独立 Memory/ETS Storage; 纯领域测试使用普通快照, 存储符合性测试使用真实 SQL 后端.

## 后置能力与保留约束

| 后置能力 | 未来引入时仍须遵守 |
| --- | --- |
| 人工采用/排除, 完整冲突协调 | 不删除报告或旧成功阻塞; 明确证据与契约依据, 原子重验并审计 |
| 自动协调规则多版本登记, 退役与治理 | 不静默改变旧 Operation 或历史决定的解释 |
| 部分取代, 处置撤销及专属授权 | 明确目标和范围, 不恢复更早处置, 不改写 Outcome |
| 计划 Authority 迁移完整流程 | 一致切点, 旧 Authority 撤权, 新 Authority 激活; 保留稳定身份和持久事实 |
| 归档清理, 管理 UI, 策略治理 | 清理不能让旧身份重新可执行, 须明确原结果查询能力 |

首版不承诺强制接管, 零停机, 外部 exactly-once, 通用 Workflow/Job 引擎或最终完成.
已有后置功能的 Quint 场景作为参考规格和回归资产保留, 不自动成为首版交付要求.

## 实现与验收

组件与部署边界见 [整体架构](runtime-architecture.md), 阶段依赖/完成条件见 [实现路线](implementation-roadmap.md).

领域纯规则接收显式事实, 时间和可信条件; Storage 在同一 Intent 的原子边界内加载, 重验并提交.
外部调用, 查询, 回调发送与通知在短事务外执行. OTP 进程组织不能替代数据库并发约束.

实现时应分别取得以下证据:

1. 领域场景: 生命周期, 结果资格, Unknown/冲突阻塞, 停止和安全重试符合规格.
2. 后端符合性: SQLite/PostgreSQL 的竞争, 事务回滚, 响应丢失重投, 时间采样和一致读取满足存储契约.
3. Handler/Adapter: 稳定键, 兼容快照, 可信来源, 回调关联及实际外部保证满足契约.
4. 组合使用: 多个 Worker/Agent 的 Intent 隔离, 以及调用方从原依赖清单恢复结果收集.

当前抽象覆盖与未验证部分见 [模型边界](../quint/README.md#模型边界). Quint 的原子存储和可信入口是前提,
不能替代真实 SQL, codec, 认证或 provider 协议的验收; 公平性与 Liveness 尚无保证.
