# Agent / Operation 持久化与恢复

状态：planning。仅创建规划；用户尚未授权激活或实施，不运行 `task.py start`，不安装依赖、不修改应用代码。

## Goal

将已经确认的持久化方案变为可验证能力：已接受输入和完整业务历史在重启后可读，恢复默认暂停，未决外部效果不自动重执行，安全 fork 创建独立新 Agent。

## Requirements

- R1：使用 Ecto，权威存储默认 SQLite、可选 PostgreSQL；执行节点 SQLite 日志仅为证据。
- R2：只新增历史记录与检查点两个 durable 原语；保存稳定 ID 和配置/secret 引用，不保存活对象或凭据值。
- R3：提交先于输入确认、派发、worker 启动和 durable completion；不存在跨库/网络原子性承诺。
- R4：保持单 attempt、不做共识/自动切主/透明重试；不确定外部效果默认阻塞，恢复只加载数据，显式继续。
- R5：完整模型请求回复、Tool 参数/结果、有序汇合及消费事实可找回；Display/Observation 与业务事实分离。
- R6：无需活进程即可审阅历史及导出固定范围可验证轨迹，来源、缺失、脱敏及继承 usage 清楚。
- R7：从安全检查点原子复制有效上下文创建独立新 Agent；原历史不变，旧身份不重定向，外部改变不撤销。
- R8：保持现有角色/宿主、临时模式和安全语义；注册 ready 不代表存储可写；两库与崩溃窗口均有实际证据。

## 子任务与需求映射

| 阶段 | 子任务 | 来源需求 | 先决阶段 |
| --- | --- | --- | --- |
| A | [持久数据契约与存储基础](../10-18-durable-storage/prd.md) | R1、R2、R3、R8 | 无 |
| B | [Runtime 权威记录与执行日志](../10-18-durable-runtime/prd.md) | R1、R3、R4、R8 | A |
| C | [Agent 历史、检查点与暂停恢复](../10-18-durable-agent/prd.md) | R1、R2、R4、R5、R8 | B |
| D | [持久历史查询与轨迹导出](../10-18-durable-history-export/prd.md) | R5、R6、R8 | C |
| E | [安全 fork 与恢复决定](../10-18-durable-fork-resolution/prd.md) | R4、R5、R6、R7、R8 | C、D |
| F | [持久化发布与运维验收](../10-18-durable-release-operations/prd.md) | R1、R3、R4、R6、R7、R8 | A、B、C、D、E |

父任务只拥有来源需求、依赖地图、跨阶段约束和最终集成评审，不直接承担全部实现。依赖顺序不由父子元数据隐式执行；各子任务的规划文件须显式遵守。

## Acceptance Criteria

- [ ] A–F 各自在真实适配器及其故障模型下验收通过，所有来源需求有子任务和最终集成证据。
- [ ] 同一条端到端路径覆盖输入 → 模型/Tool → 证据落盘 → 权威接受 → 一次消费 → VM 重启 → paused restore → 显式继续。
- [ ] unsafe/unknown/shared-environment 风险不会导致自动补跑；迟到证据不覆盖 accepted Result、不推进 fork 的新 Agent。
- [ ] 真实 fork 独立恢复，原历史保留；导出区分继承上下文/实际执行，不依赖父链。
- [ ] 两种权威数据库对幂等、CAS、回滚、排序和恢复产生同一业务结果，资源上限与环境限制有记录。
- [ ] 最终实现仍为八张权威表 + 一张 executor 日志表，不增加 Branch、Workflow、Display/Observation 表或通用 replay 引擎。

## Out of Scope

分布式共识、自动故障转移、数据库复制协议、跨物理主机保证、外部效果 exactly-once、自动业务重试、撤销外部改变、可执行导入、对象存储/GC 调度、评测/训练平台和完整 token 重放。不得把同主机 peer/kill-VM 测试称为跨物理主机或断电证据。

## 设计依据

- [主设计](../../../docs/architecture/agent-operation-persistence.md)
- [实施与验收计划](../../../docs/architecture/persistence-delivery.md)
- [术语](../../../GLOSSARY.md)

以上文档是契约来源；本文只收敛本任务范围，不另建相互竞争的设计。代码兼容性核对基线为 `a078aa3`，开工前重新核对后续变化。
