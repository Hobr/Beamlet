# 提取 Agent 纯业务内核 beamlet_agent_core

## Goal

将 Agent 的事件归约、上下文策略和已有业务决策从运行适配中分离，使其可以在不启动 Agent、Runtime、Repo 或 provider 的情况下使用和验证，保留当前对外行为。

## Background

- 用户明确放弃 beamlet_computation，选择讨论 Agent 专属内核；本轮明确要求重新创建任务。
- 当前基线为 dev / a18f3c7488e08c13a4fc324e602e0a75d67e20bf，已包含 durable rebuild 及直接引用 fork/history/export。
- 旧任务记录及实现工作消失，当前只有空目录；本任务为重新建立的规划，不能声称恢复了原始文档或验证结果。

## Requirements

- R1：提供独立 umbrella 库 beamlet_agent_core，核心业务计算不依赖 Agent 进程、Runtime、Storage 或 Ecto，不触发外部 I/O。
- R2：事件归约维护 Agent 专属状态、不变量和版本规则；持久化编码及摘要校验由运行适配提供，历史语义保持一致。
- R3：上下文读取与构建分离。运行层验证并加载明确来源的材料，Core 根据已选时间线和材料构建统一消息、sources、policy；正文不进入长期控制状态。
- R4：抽取现有纯决策，至少覆盖模型回复对应的继续位置及暂停恢复位置分类，并由运行层实际调用；不引入新的通用编排框架。
- R5：现有公开 Agent 接口、错误契约、事件及快照版本、摘要、Operation 内容和准备/采纳/消费事务语义兼容。
- R6：保留输入、模型/工具限制、完整批次验证、执行不确定性、固定请求恢复、已消费来源约束、fork 继承和环境风险确认行为。
- R7：运行层保留进程、资源生命周期、部署配置、credentials、事务、读取和执行职责；预演不得推进正式状态，正式投影只应用提交返回的事件。
- R8：保留现有 memory 模式及 delegation/peer 行为，不扩大其 durable 保证。

## Acceptance Criteria

- AC1 (R1)：Core 可通过显式数据执行归约、上下文构建和决策；测试不启动 Repo、Agent、Runtime/provider，依赖中不包含 Storage/Runtime/Agent/Ecto。
- AC2 (R2,R5)：相同历史经旧适配接口和 Core 归约得到一致状态；非法顺序、未知版本、错误关联明确拒绝，错误不因拆分被放宽。
- AC3 (R3,R6)：材料来源缺失、乱序、重复、非选定来源被拒绝；正常输入/结果及继承来源得到原有消息和 policy；未消费输出不进入上下文。
- AC4 (R4)：运行路径使用 Core 决策，文本/工具回复、可继续/阻塞位置及错误分类与原行为一致。
- AC5 (R5-R8)：现有 durable、fork/history/export、运行生命周期和产品集成回归通过；无删除或弱化既有断言。
- AC6 (R7)：失败/冲突提交不推进正式状态；inspect/replay 不执行操作，恢复使用固定请求。
- AC7 (R1,R5)：新应用纳入普通和 backend 构建闭包，相关文档和规范说明实际依赖与纯计算保证。

## Out of Scope

通用 Computation/工作流框架、DSL、新 provider、流式协议、自动重试/补偿、存储格式升级、改变调用顺序或限制、将 delegation/peer 变成 durable、新建 Harness contracts 库。

## Planning Status

用户已在重新创建方案的最终审阅摘要之后明确回复“批准”，授权进入实施。旧子代理结果不能作为有效代码或测试证据。
