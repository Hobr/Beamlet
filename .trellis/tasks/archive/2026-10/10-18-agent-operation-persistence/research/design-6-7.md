# 持久化设计原文快照：事务与恢复（6–7）

用途：规划上下文分片，避免 Trellis 单文件 32768 字节注入上限截断主设计；不是第二份权威设计。节选只调整相对链接以适配本目录，不改变原契约。

来源：[主设计](../../../../docs/architecture/agent-operation-persistence.md) 在 2026-10-18 文档修补后的工作树内容，代码兼容性基线 a078aa3。以下为对应章节原文；开工前须对照当前主设计检查差异。主设计更新时应重新生成受影响分片，不以旧快照覆盖新契约。全部章节的整体关系见[父设计](../design.md)与[交付计划](../../../../docs/architecture/persistence-delivery.md)。

---

## 6. 事务与提交顺序

持久写入接在业务转换处，而非 `publish`、`publish_activity` 或观察订阅处。当前 `Agent.Server.complete/3`、`complete_tool/3`、`batch/2` 负责模型回复、结果汇合及批次推进；durable 接入须在对应状态转换中组织事务。Coordinator 的 `accept/2` 必须提交终态后再通知 sink；Gateway 必须在启动 worker 前和上报终态前分别完成本地提交。展示发布只读取提交后的业务状态，可合并或丢弃，不参与恢复正确性，也不替代输入确认或 durable Result 通知。

### 6.1 输入及 Tool 批次

输入接受事务同时写 command 去重、输入 message、turn、事件和继续位置。仅在提交后返回“已接受”。响应丢失时调用方以同 command_id 查询/重试，仅重读既有提交，不再次调用模型。

模型完整回复必须先落盘，再完整验证整个 Tool 批次；任何一个 Tool 参数不合法均为零派发。合法批次在一次事务中创建全部 Operation 和 tool ordinal/join manifest，然后才允许各自派发。先存模型回复可以在崩溃后重新做纯验证，但不能重新请求模型来获取这份回复。

### 6.2 权威派发

1. 将 Operation、attempt、目标及 Execution 的派发状态在权威库提交为 `prepared`。没有可选目标可提交 coordinator-origin `no_target`，无 Execution。
2. 协调器以 CAS 将 Execution 从 `prepared` 改为 `send_claimed`，提交后才发送一次 admit。不得在数据库事务内发消息或调用外部系统。
3. admit 带稳定 authority/operation/attempt ID、目标 boot 关联及描述 digest。凭据在发送前临时解析，不写 Execution 记录。
4. `send_claimed` 后崩溃，无法证明发送与否；恢复只查询该 attempt，不能自动重发。`prepared` 尚未 claim 表示尚未发送，恢复后可由显式 continue 继续该步骤。
5. admission 观察、取消请求、接受终态均在权威库提交，再通知 Agent/UI。

数据库事务和网络发送之间的缝隙无法消除。这里主动选择可能暂停一项尚未执行的工作，避免自动重发一项可能已产生副作用的工作。Execution 上的派发状态只解决“提交前不能发送”和可审阅性，不是独立 outbox，不提供 exactly-once。

### 6.3 执行节点：本地日志是持久模式的默认要求

权威库只能证明自己保存过什么，无法保留执行节点完成但尚未上报的结果，因此持久执行模式默认要求本地 SQLite 日志。单机组合角色也走相同协议、独立日志接口；不增加绕过路径。

1. Gateway 在本地串行准入中验证，暂占内存容量，落盘 admission 和 `start_intent`；写失败则释放容量并明确拒绝，零 handler 调用。
2. 提交 `start_intent` 后才启动 worker。worker 不承担“启动前第一笔写库”的责任。
3. 同 attempt 重复消息只返回既有证据，不启动第二个 worker。状态只到 admission/start_intent 的旧记录也不允许重启后补跑。
4. worker 返回规范化 Result 后，Gateway 将终态值/输出 artifact 与 receipt 原子落盘，之后才上报。若写入失败，不能上报为 durable completion；保留有界内存重试写入并撤下持久就绪能力，进程丢失后保持 unknown。
5. 权威收到 receipt 后先持久化 evidence，再按终态接受规则处理；持久 ACK 只证明证据已存入权威库。执行节点可重传 receipt，这是数据传输重试，不是 handler 重执行。
6. Gateway/VM 重启后原活跃 start_intent 记录变为 `unknown_after_restart`；不重建 worker、不按历史占用恢复容量。只有当前 worker 实际占用本机槽位。

权威收到的证据必须匹配保存的 authority/operation/attempt/executor ID 与描述 digest，经可信 executor 路由验证；损坏、冲突或身份不匹配的 receipt 不可参与自动接受，留下安全错误和有界诊断。恢复时重新发现的 endpoint 只能承载稳定身份的查询，不代表旧 worker 仍存在。

从真实外部改变到本地终态提交之间仍可能崩溃。即使有本地日志，也不能从 start_intent 推断“未执行”，不能承诺副作用和日志原子性。`not_found` 仅是该日志的数据观察，尤其磁盘丢失/备份回退时不能作为安全重试证明。

停止原因沿用当前 Gateway 契约：第一个由 Gateway 处理的 deadline/cancel 触发原因拥有停止 provenance；后续触发不覆盖它。只有观察到与本次停止请求相符的 worker 终止，才能形成 execution-origin 的 `deadline/worker_stopped` 或 `cancelled/worker_stopped`。无关崩溃仍为 `error/worker_lost`，竞态中的正常返回仍可为 success，不能因为已经请求停止就改写结果。规范化终态连同已观察的停止原因、终止事实与 receipt 同事务保存；已记录的停止观察也保留在日志中。日志写失败或终态保存前崩溃仍按 unknown 处理，不能由请求记录推断“已经停下”，也不能为等待写库而取消尽力停止措施。

### 6.4 终态接受与消费

权威事务以 `accepted_result IS NULL`、expected_version、当前写入代次作为条件更新 Operation，并写 `result.accepted` 事件。影响行数为零时重读既有值；同证据幂等返回，冲突证据留审阅记录，不能覆盖已接受终态。

若先接受了 uncertain/deadline，而后得到真实 success，保留原 Result；新增 evidence/resolution。用户可以显式采纳该证据推进仍暂停的上下文，记录决定与来源；历史上当时接受的 Result 不变。已经停止的轮次或 fork 的源 Agent 绝不因迟到证据自行继续，源 Agent 的证据也不能推进新 Agent。

当前内存实现会将 Tool 的不同 Result 状态编码成观察，再交给模型继续；持久接入不能无条件复用这一推进路径。Coordinator-origin 的 `deadline/termination_unconfirmed` 和 `uncertain/cancel_unconfirmed` 不是 executor 已停证明，与 execution-origin 的已观察停止须明确区分。

持久模式默认将涉及外部效果的 uncertain、未确认停止或日志缺失设为轮次 blocker，不把它伪装成普通 Tool failure 交给模型自动再做一次。用户可显式选择采纳已核实证据、放弃该步并保存中断观察，或承担风险发起关联的新 Operation。若 uncertain 尚未消费，resolution 决定最终进入上下文的观察；若已经显式消费过中断观察，后续证据只能作为新的带来源纠正消息加入，不能覆盖旧 message 或重复占用原 Tool result 槽位。

Agent 消费 Result 的事务同时保存 Tool message、consumed 标记、join 顺序和检查点/下一继续位置。唯一(agent_id, operation_id, consumption_kind) 防止重复进入上下文。消费时必须校验 Operation 的 owner Agent/turn，源 Agent 的 Operation 不可作为新 Agent 的待消费工作；fork 复制的旧返回值是继承消息，不再次触发消费转换。保存 Result 后 Agent 崩溃，恢复只完成尚未消费的数据转换。并发 Tool 结果按原 ordinal 构造上下文，不按到达顺序。

取消首先保存 request，冻结该轮次后续派发，再发尽力停止消息。取消请求不是 worker 已停、也不是撤销外部改变。即使取消成功，已接受的成功结果仍保持成功。

## 7. 恢复模型与继续位置

区分三个动作：`inspect` 只读恢复计划，`restore` 建立新的暂停实例，`continue` 显式推进。启动角色树仅恢复 Repo、发现与查询能力；默认不批量启动所有历史 Agent，不自动调用 handler。

### 7.1 恢复流程

1. 核对 authority_id、schema、备份恢复标记和独占部署；数据库不可用则禁止相应持久输入/派发准入，不以 Node services 的注册 ready 代替此判断。
2. 读取当前 head checkpoint，验证其数据版本、消息/artifact 引用，并核对其中 pending/consumed 集合与权威 Operation/证据。无需重放历史事件。
3. 返回普通恢复说明数据（RecoveryPlan），列明 pending Operation、终态未消费、未决派发、缺少 secret/profile/environment、子 Agent/peer 不可达等事项。它不是持久实体或独立执行计划 DSL。
4. 激活时在权威事务内增加 generation，保存恢复事件；本地恢复控制器串行化同 Agent 激活，以 Registry/监视确认旧本地进程已经退出，再建立新暂停实例。仅 CAS 不能阻止旧进程在提交之后发送消息。
5. 对未决 attempt 可自动做只读证据查询；查询使用 executor_id/attempt_id，不重新 admit，不恢复原 PID。目标不可达保持 blocked/uncertain。
6. `continue(expected_version, decisions, command_id)` 检查 Agent/相关 Operation 版本、配置兼容与 pending 风险；提交决定后推进明确的继续位置。冲突返回新的恢复说明，不隐式采纳用户未见的新证据。

恢复并非强制重新生成所有消息；有效历史和上下文已经在权威库中。必须维护以下可版本化继续位置：

| 位置 | 恢复动作 |
| --- | --- |
| `await_input` | 暂停实例等待新输入 |
| `model_prepared` / `tool_batch_prepared` | 显式继续后可 claim 尚未发送的派发 |
| `await_model_result` / `await_tool_results` | 查询证据/等待，绝不重新发送已 claim 的 attempt |
| `reply_recorded` / `results_to_consume` | 仅做纯数据验证/上下文转换，按消费键幂等 |
| `ready_for_next_step` | 显式继续后创建下一项新 Operation |
| `await_delegation` / `await_peer` | 查询远端历史或等待显式解决；不重建子 Agent、不重发消息 |
| `interrupted` / `blocked` / `completed` | 不自动推进；展示原因和允许的显式动作 |

最终模型回复的消费可以触发下一轮 Tool，但只有持久化的完整参数经全批验证后才能如此做。已有 Operation Result 与未生成的新 Operation 之间必须由继续位置区别，避免“恢复消息”变成重执行。

### 7.2 预算、环境、委派与重试

运行中的 budget 使用本 VM 单调时钟，永不持久化绝对 monotonic timestamp。保存原预算、已观察 elapsed 和 UTC 审计时间；停机后不尝试恢复原 timer。已 claim 的工作默认按 interrupted/uncertain 处理；需要新工作时显式给新 Operation 新预算，并记录 predecessor。跨机 UTC 不用于证明 worker 已停。

环境引用不是环境快照。Shell session/provider instance 不能重新绑定到同路径的新环境；恢复必须由 provider 校验稳定环境身份/版本，可选返回 `unavailable` / `changed`。环境缺失不会触发其他节点或沙箱回退。

父子 Agent 可能在不同权威库中，关系事件仅记录本方观察和因果关联。父 Agent 恢复不会启动/继续/关闭远端历史子 Agent；逐个显式恢复。peer 消息首版不提供可靠投递和自动重发；未完成请求恢复为 interrupted，显式新请求使用新 message_id。不得重建过期 TTL 或复活旧收件箱。

同一 Operation 首版仍最多一个 attempt。人工决定重试时创建新 Operation（`retry_of` 关联和明确风险接受事件），不改原 Operation、不给原 attempt 第二次机会。provider 的无副作用读取/receipt 传输重试与业务 handler 重执行必须分开。
