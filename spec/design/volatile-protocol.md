# 非 Durable 多节点协议草案 v0

状态: 内存原型已完成应用 -> Agent -> 执行驱动 -> 纯 Kernel 的分层, 并提供可独立驱动的 Authority/Worker 消息入口. 原有 40 项及新增 6 项消息流用例通过; 两个应用入口都通过兼容的本地 Agent 跑通了 100 个 Operation. 新消息流使用同进程有界通道验证, 三进程通信尚未实现; 这不是已发布协议, 也未经形式化验证.

## 1. 范围与身份

首版目标是验证三个进程: 一个 Authority, 两个 Worker. 只使用受信测试网络和固定的 echo, delay, fail 测试任务; 执行状态全部在内存中, 不依赖数据库恢复.

暂不实现能力注册, 发现, 版本, 输入输出契约或性质声明. 两个 Worker 均内置上述三个测试分支, 不建立可扩展处理器注册接口.

Authority 接纳 Operation, 生成执行授权, 选择 Worker, 并收集同一 Operation 的 Report. 跨 Operation 的业务汇总不属于本协议. 一个进程可以兼任两种角色.

| 身份 | 生成方 | 含义 |
| --- | --- | --- |
| OperationId | 提交方 | 不可变逻辑请求的身份; 提交重试沿用原 ID |
| AttemptId | Authority | 一次执行授权的身份; 重投原授权沿用原 ID |
| ReportId | Worker | 一份执行证据的身份; 重复回报沿用原 ID |
| RoleInstanceId | 启动方 | 为本次进程运行分配的身份; 每次重启更换, 区别于配置别名或连接地址 |

启动方通过静态配置向 Authority 提供 Worker 的连接地址与本次 RoleInstanceId, 不引入节点登记或自动发现握手. 重启后必须更新相应配置, 不自动接续旧任务.

本原型中, Operation 的业务定义由固定测试任务种类, 输入与约束组成; 相同输入不代表相同 Operation. 新需求使用新 OperationId.

## 2. 三类业务消息

每条消息包含协议版本 `protocol_version = 0`, `source_instance_id`, `target_instance_id` 和 `message = {kind, body}`. kind 为 submit_operation, dispatch_attempt 或 submit_report; body 字段见下表. 运行实例身份用于路由与关联, 不构成身份认证机制.

| 消息 | 方向 | 必需业务内容 |
| --- | --- | --- |
| SubmitOperation | 提交方 → Authority | operation_id, task, constraints |
| DispatchAttempt | Authority → Worker | attempt_id, 完整 Operation 定义及 operation_id |
| SubmitReport | Worker → Authority | report_id, operation_id, attempt_id, outcome, effect, 以及 output 或 error |

`task` 仅为固定测试数据 `{kind, input}`: echo 回显 JSON; delay 接收 `{delay_ms, value}`, 在指定延迟后返回 value; fail 接收 `{message}` 并返回测试错误. 这不是能力描述, 动态注册或插件协议.

输入输出先使用 JSON. delay_ms 必须是非负整数且不超过配置上限; 错误信息与其他输入均受大小限制. 约束首版仅支持空集合; 不能识别的协议版本, 任务种类, 消息或约束必须显式拒绝, 不能静默忽略. 首版不自动重新授权执行.

Report 的字段含义:

- `outcome`: `succeeded`, `failed` 或 `rejected`, 描述处理结果.
- `effect`: `none`, `observed` 或 `unknown`, 描述现有证据对外部效果的判断; `observed` 不承诺完整成功或仅发生一次.
- `output` 与 `error`: 成功提供 output, 失败或拒绝提供有界错误信息.
- 错误或超时不自动推导为 `effect = none`; 缺少确定证据时使用 `unknown`.
- `rejected` 仅用于执行器在运行处理函数之前明确拒绝, 效果必须为 `none`.

### 响应不是新的业务动作

提交与回报可以返回关联原业务 ID 的 ACK 或错误. ACK 仅表示本次进程在内存中完成了相应接收, 不表示落盘, 执行成功或取得未来恢复保证. 下面描述的是接口语义, 不代表三段网络回执都已实现: 当前 Node 已实现 Operation 接纳, Attempt 接纳和 Report 收录三段回执及其易失性有界重投, Console 使用 SubmissionKey, OperationId 由 Authority 生成, 详见 [三段回执契约](receipts.md). 本文通用内存驱动本身仍不负责网络重投.

- SubmitOperation 被接纳: 返回 operation_id 与唯一的 attempt_id; 同一进程内的相同重复提交返回已有关联.
- SubmitReport 被接纳: 表示已进入本 Authority 的内存记录, 不等于无条件采用为业务成功.

通用内存驱动本身不发网络 ACK; Node Adapter 已接入独立 Attempt 接纳回执. 仅有发送返回时 Authority 只能声称"已发出", 收到匹配接纳回执可声称"Worker 已接纳", 仍不能据此声称"正在执行".

结果查询是 Authority 的本地接口或测试入口, 按 OperationId 读取内存视图; 首版不另建跨节点查询协议.

## 3. 必须保留的协议规则

1. **身份不可变.** 相同 OperationId, AttemptId 或 ReportId 的重复内容必须一致; 业务定义不同则报身份冲突, 不覆盖旧记录. JSON 对象的空白与字段顺序不参与业务定义比较.
2. **单次授权.** 每个被接纳的 Operation 首版只生成一个 Attempt, 并固定 Authority, 目标 Worker 运行实例和测试任务定义; 不竞速, 不自动换节点, 不自动产生第二个 Attempt.
3. **执行关联检查.** Worker 检查目标实例, 已配置的受信 Authority, 固定任务种类与输入; Authority 检查 Report 的来源实例与 Operation/Attempt 绑定. 旧运行实例的消息不得自动绑定到重启后的新实例.
4. **进程内去重.** Worker 对排队, 运行, 已完成的 Attempt 去重, 不因重复派发再次运行; 已完成时可重发缓存的同一 Report. Authority 去重 Report, 额外或冲突证据不能静默覆盖已有记录或结果.
5. **资源有界.** 输入输出, 队列, 并发数, 请求与证据记录数量都有配置上限; 不静默淘汰仍用于去重的记录. 容量不足时显式拒绝或返回背压错误, 不无限创建任务.

请求在接纳前验证协议版本, 固定任务参数和容量; Authority 仅从静态 Worker 列表中选择目标. Worker 对未知任务或无效输入明确拒绝; 本协议不提供任意代码执行.

Authority 的基本视图为 `accepted → dispatched → reported`. 等待超时单独记录, 不当作执行失败, 取消成功或未产生效果; 迟到 Report 仍校验, 收录并更新视图. Report 的采用由 Authority 决定, 不由传输 ACK 决定. 当前内存原型选择首份绑定合法的 Report 作为观察结果, 不将其自动解释为业务成功; 额外证据保留, 但不自动替换已选结果.

## 4. 一个完整例子

1. 启动方为 A, B, C 分配本次运行身份, 向 Authority A 注入 Worker B, C 的地址与实例 ID. B, C 均内置 echo, delay, fail; A 简单轮询静态列表, 不做注册, 发现或健康评分.
2. 提交方发送 O1: `task = {kind: "echo", input: "hello"}`. A 保存内存关联 O1 → T1 → B, 返回接纳响应, 然后派发 T1.
3. B 按队列与并发限制运行 T1; 相同 T1 重复到达只关联现有执行. B 完成后生成 R1, 并向 A 回报.
4. A 检查 B, O1, T1, R1 的绑定, 保存证据与采用决定; 提交方按 O1 查询结果. 若提交方等待已经超时, R1 仍可到达并更新结果.
5. A 之后接纳独立请求 O2, 生成 T2 并分配给 C. 这里是多个独立 Operation 的路由, 不是把 O1, O2 合成一个业务工作流.

## 5. 故障边界与首个验收

本协议不承诺最终交付或崩溃恢复:

- Authority 重启丢失内存请求, 授权与结果; 静态配置可以重新加载, 但不恢复执行记录, 重复提交不再获得跨重启去重保证.
- Worker 重启丢失执行进度与去重记录, 且获得新的 RoleInstanceId; 旧 Attempt 不自动重绑定或恢复.
- 断连, 丢消息或等待超时只产生未决状态; 不触发自动重新派发, 改派或重新授权.
- 无后台可靠重投队列, Outbox, 自动接管, 补偿编排, 真实 LLM 或 GUI.
- 稳定 ID, 进程内去重和传输可靠性均不构成外部效果 exactly-once 保证.

验收用例:

1. 三个进程处理 100 个独立 Operation, 两个 Worker 均执行任务, 结果可按原 ID 查询.
2. 同一 Operation 重复提交不增加 Attempt; 相同 ID 携带不同定义被拒绝.
3. 重复派发同一 Attempt 只运行一次; 重复 Report 不重复采用, 错误绑定被拒绝.
4. delay, fail, 超时后的迟到 Report 与容量不足均有明确可观察结果, 不串请求, 不无限堆积.
5. 终止一个 Worker 后, 相关请求保持未决; Authority 不偷偷改派或生成新的 Attempt, 重启实例不接续旧授权.

## 当前实现与复验

依赖方向:

```text
app/beamlet-console, app/beamlet-node
                  ↓
          agent/beamlet-agent
                  ↓
           kernel/beamlet
                  ↓
        kernel/beamlet-kernel
```

当前职责:

- 纯领域: [id.rs](../../kernel/beamlet-kernel/src/id.rs), [model.rs](../../kernel/beamlet-kernel/src/model.rs), [state.rs](../../kernel/beamlet-kernel/src/state.rs). 身份是调用方提供的 128 位值; 领域对象使用不透明的输入, 输出与错误类型; 拒绝效果和完成阶段规则不依赖 JSON, UUID 库, Tokio, 数据库或传输.
- 底层实现: [memory.rs](../../kernel/beamlet/src/memory.rs) 提供有界内存 Authority/Worker, 静态轮询, 去重和证据保留; [executor.rs](../../kernel/beamlet/src/executor.rs) 提供通用 Tokio 驱动, 每个 Worker 有独立上限, 共享有界的在途完成集合. 执行函数由调用方直接传入, 不创建能力注册表.
- 应用入口: [beamlet-agent](../../agent/beamlet-agent/src/lib.rs) 提供可独立驱动的 [Authority](../../agent/beamlet-agent/src/authority.rs) 与 [Worker](../../agent/beamlet-agent/src/worker.rs), 以及保留旧行为的本地 Agent 组合. 应用只依赖该 crate 即可提交, 交付授权, 执行并收录证据; 不实现自主 Agent Loop.
- 测试 Adapter: 显式启用 test-support 后, [protocol.rs](../../agent/beamlet-agent/src/testing/protocol.rs) 提供严格 v0 JSON 与领域转换, [memory.rs](../../agent/beamlet-agent/src/testing/memory.rs) 提供协议校验和只读投影, [executor.rs](../../agent/beamlet-agent/src/testing/executor.rs) 提供固定 echo/delay/fail. 默认 Agent 构建不包含这些模块. UUID 字符串的传输表示不变, 纯领域身份通过 from_u128 构造.
- 应用组装: [node](../../app/beamlet-node/src/main.rs), [console](../../app/beamlet-console/src/main.rs) 与原有 [volatile 示例](../../app/beamlet-node/examples/volatile.rs) 暂时调用同一份 [Agent 演示用例](../../agent/beamlet-agent/src/testing/demo.rs). 各入口均完成 100 个独立请求, 两个 Worker 各完成 50 个; 67 个成功, 33 个为预期失败. 它们还不是网络节点或交互式 Console.

原有 app/beamlet-node/src/protocol.rs, memory.rs, executor.rs 只保留兼容导出, 不再持有实现. 原有 21 项协议/内存测试和 11 项异步执行测试保留在应用集成测试入口; 新增 4 项纯领域测试和 4 项 Agent 入口测试. 新增 Agent 测试只导入 beamlet-agent, 不使用 JSON 或固定假任务类型. 不将重复测试入口计作新增覆盖.

### 独立消息入口

Authority 与 Worker 分别持有状态, 不相互引用, 也不直接修改对方的记录. Agent 保留为单进程本地组合, 需要自行交付消息时使用两个独立入口:

1. Authority::submit 接纳本地应用 Operation, 返回待交付授权, 不向 Worker 入队或自动发送消息.
2. 调用方交付授权后调用 Authority::mark_dispatched, 只记录已发出, 不声称 Worker 已接纳.
3. Worker::receive_dispatch 校验并入队; 排队或运行中的重复授权不重复执行, 已完成的重复授权返回缓存的原 Report.
4. Worker::next_report 使用调用方提供的普通执行函数, 缓存完成证据后返回待交付 Report, 不直接修改 Authority.
5. Authority::receive_report 校验并保留收到的证据, 再决定采用结果. Worker 完成与 Authority 采用是两个独立事实.

交付方负责处理发送失败或背压, 本轮没有待发队列, 可靠重投或恢复机制. 通道已满时, 尚未发出的请求保留为 accepted, 重复提交只返回原授权, 不自动重投或产生新 Attempt.

[消息流用例](../../agent/beamlet-agent/tests/message_flow.rs) 只通过 beamlet-agent 公开入口和容量为 1 的 Tokio 通道交互, 不导入底层 crate. 六项用例覆盖独立 echo, 重复交付与缓存证据, 取消等待及迟到证据, 交付背压, 非法消息与证据冲突, 两个独立 Worker 的乱序关联. 延迟使用 Tokio 虚拟时间, 这些测试不是跨进程或断网验证.

复验独立用例, 共 46 项:

```bash
cargo test -p beamlet-kernel --offline --test primitives
cargo test -p beamlet-agent --no-default-features --offline --test execution --test message_flow
cargo test -p beamlet-node --offline --test volatile --test executor
```

运行两个应用入口, 或保留的单进程示例:

```bash
cargo run -p beamlet-node --offline
cargo run -p beamlet-console --offline
cargo run -p beamlet-node --offline --example volatile
```

兼容的本地 Agent 负责 submit, next_report, 查询和等待超时标记, 内部组合上述两个独立入口. next_report 会启动有空闲槽位的任务, 缓存完成证据, 再交给 Authority 收录. 取消等待不会取消已启动执行. 任务完成但 Worker 尚未缓存证据时仍占用并发槽位; 不要求等待 Authority 收录才释放槽位. 后台异常作为内部错误返回, 调用方应停止该执行器, 不伪装成普通失败或自动重跑.

Authority 接纳与 Worker 入队不是同一事实. Agent 提交时若 Authority 已接纳而 Worker 因队列已满拒绝, 请求仍保留为 accepted; 重复提交返回原授权, 不自动重投或生成新 Attempt. 该未决情况有独立测试, 不声称已经执行, 也没有持久交付保证.

三种假任务均无外部效果, 因此明确使用 effect = none, 而不是从成功或失败推导效果. v0 测试 Adapter 在入账前检查派发大小, 假任务执行 Adapter 在入队前试算完整报告大小; 超限时不创建对应的新记录, 不截断结果. 试算不是执行或完成证据. 通用领域与执行驱动没有 JSON 字节上限或 delay 参数语义, 具体编码及输出预算必须由实际 Adapter 负责.

丢弃执行器会中止未完成的本地任务并丢失内存记录. 这些结果尚未证明三进程通信, 断网, 崩溃恢复或真实 Tool 效果; 后续再接 Zenoh, 不扩展能力或 Durable 范围. 本文不规定最终发布兼容策略.
