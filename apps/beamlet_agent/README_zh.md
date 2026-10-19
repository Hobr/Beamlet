# Beamlet Agent：显式 authority 与可暂停编排

[English](README.md) · [Runtime](../beamlet_runtime/README_zh.md) · [Node](../beamlet_node/README_zh.md)

Agent 拥有一次活动 turn 的模型/工具编排、身份、订阅和委派，以及可选持久化输入与消费控制。Runtime 拥有中立 Operation 执行；Harness 拥有原生模型/工具契约；Core 拥有纯事件归约、上下文转换和继续决策。直接依赖 Agent Storage、Storage、Ecto、Jason、Core、Actions、Runtime、Harness，不依赖 Node 或具体宿主。

## 前提与内存调用

在仓库根目录进入 `nix develop`（OTP 29 / Elixir 1.20），首次运行 `mix deps.get`、`mix compile`。本库没有 Application 回调。宿主显式安装 AuthoritySupervisor（身份岛）及 Runtime；需要执行时配置相应能力/处理器。最小手工接线可在尚无 Node/Runtime 的根目录 `iex -S mix` 执行：

```elixir
{:ok, tree} = Supervisor.start_link([
  {Beamlet.Runtime, execution: true,
    handlers: %{"agent.native" => {Beamlet.Agent.Integration.Handler,
      %{profiles: %{}, model_providers: Beamlet.Harness.Model.default_providers()}}},
    capabilities: ["model.provider:deterministic"]},
  {Beamlet.Agent.AuthoritySupervisor, []}
], strategy: :one_for_one)
binding = %{provider: "deterministic",
  config: %{"reply" => %{"kind" => "text", "content" => "你好", "calls" => []}}}
{:ok, ref} = Beamlet.Agent.start(node(), id: "example", model: binding)
:ok = Beamlet.Agent.subscribe(ref)
receive do
  {:beamlet_agent, ^ref, sequence, {:snapshot, initial}} ->
    :ok = Beamlet.Agent.ack(ref, sequence)
    initial
end
```

Directory 报告是异步的。先用 `Beamlet.Runtime.observation/0` 观察 fresh/ready 的能力报告，再单次 `{:ok, turn} = Beamlet.Agent.input(ref, "hello")`，持续接收该 Ref/turn 的替换快照并确认序号，直到终态。示例不访问外部模型。也可由 [Node](../beamlet_node/README_zh.md) 组合角色，避免重复启动监督树。

每个 Agent 的 model 绑定固定，含 provider/config 与可选 credentials/placement；authority 只解析自身可信 provider 注册表。凭证仅瞬时传递，不保存到 definition、描述、来源、正常历史或快照；恶意 provider 回显及管理员进程检查不在保密保证内，也不承诺安全擦除。工具使用公开 profile/capability/environment/claims/allowed_nodes 路由，本地 settings/工作区根留在执行器。配置版本摘要排除消息、工具参数与凭证，但包含模型配置、目录与可移植配置；它不检查 executor 根或适配器代码。

## 生命周期与额度

AuthoritySupervisor 用 one_for_all 耦合 Registry、Resources、Delegations、Agents；最多 128 Agent，Registry 丢失使旧实时 Ref 失效。Ref 包含真实 authority/id/pid/incarnation，不是可在重启后重建的定位符。`start/2` 显式选择 authority，创建失败不选择替代节点；`close/1` 关闭实时实例，不删除持久化事实。

单输入最多 65536 UTF-8 字节；原生上下文最多 128 消息/1 MiB，超限拒绝，不驱逐完整 assistant/tool 配对。每 turn 最多 16 模型步骤、8 工具；完整回复与兄弟批次验证后才分派，独立工具并发，按调用 ID 关联并按原 ordinal 加入上下文。活动 turn 输入返回 busy。不确定/cancelled/deadline 结果阻止自动后续工作；内存 Agent 不支持持久化决策恢复，需创建新实例，不能猜测执行失败后重试。

所有权控制器把阻塞 Runtime submit/ack 放在 linked worker 中，登记/准入预算 5 秒，总生命周期 65 秒。Resources 分别限 1024 operation/delegation 组，每 Agent 最多保留各 8。业务 Result 接受并不释放整个资源组；必须观察所有成员 DOWN 后才退休，后续调度异步等待。authority 替换先清退 VM 内旧 PID 清单，清单不是业务重放存储。定时器预算不是硬实时保证。

`stop_turn(ref)` 冻结旧 turn 并请求尽力清理；持久化活动 turn 会记录中断并暂停。`:ok` 不能证明远端终止、无副作用或账单停止。Runtime 没有自动业务重试；断连、准入超时、未知提交均可能代表已执行。匹配旧 turn/attempt/Ref 的迟到消息不能推进新 turn。

## 订阅、展示与身份发现

消息是 `{:beamlet_agent, ref, sequence, {:snapshot, snapshot}}`，基础快照含 ref/turn/terminal_turn/status/steps/final/progress。初始快照先于同发送者更新；消费 sink 自身调用 `Agent.ack(ref, sequence)`。最多 32 sink，各最多 16 未确认序号，慢 sink 只收到合并后的当前快照；sink DOWN 只移除订阅，不停止 Agent，没有事件历史回放。`unsubscribe/2` 删除订阅。

`snapshot(ref, view: :display)` / `subscribe(ref, sink, view: :display)` 可选展示投影，最多近期 32 条消息、16 活动、每字段 8192 UTF-8 字节，display 总 131072 字节，完整快照保守预算 1048000 字节。预算不足裁剪展示，不改模型请求或基础 final/progress。请求 display 后收到无 display 的替换快照必须清除旧展示。coverage 仅 live_context，ID 属于当前实例；pending 不证明执行器已准入，placement 当前 unknown，终态活动会消失。公开 display_metadata（title/preset_id/option_ids）整体最多 4096 字节，不独立证明来源或授权，所有文本应按不可信内容转义。

`Agent.list(authority)` 返回最多 128 个 `%{authority: node, id: binary, pid: pid}` 描述符，不逐一等 Server。`Agent.lookup(authority, id)` 取得当前真实 Ref；`Agent.lookup(descriptor)` 额外拒绝替换 PID 为 stale_agent，不自动重建实例。ID 为 1..128 UTF-8 字节。查询有限 5 秒，仅远端入口时已连接才查询，完整返回最多 1 MiB；invalid_query/not_authority/not_found/unavailable/timeout/stale_agent/limit 都是明确错误。查询进程与身份岛隔离，不会因查询退出重启 Agent。OTP 可在连接预检后重连，远端延迟执行从自身入口开始有限预算，调用者放弃不代表远端立即取消或 mailbox 撤回。

## 委派与 peer mailbox

`Agent.delegate(ref, [%{authority: node(), options: child_opts, input: "任务"}], continue: false)` 接受 1..8 子项。每子项独立绑定与凭证；父级只验证通用可移植数据，创建 authority 才验证本地适配器，不要求两边注册表相同。父级明确 startup 授权后才输入；创建拒绝返回关联 authority_unavailable，不重试。默认按原顺序返回结果列表，continue: true 把观察加入上下文再继续；等待父级不持有 executor 容量。停止/失联触发子树清理，不能证明外部副作用停止。

`peer_request(ref, target, payload, ttl)` 返回关联 ID，`peer_reply` 回复，`inbox` 查看，`peer_take` 取出并删除（缺失是 {:ok, nil}）。TTL 1..60000ms，pending+inbox 最多 16，完整线缆及带键保留信封最多 8192 字节。它们是 mailbox 数据，不是隐式输入或工具；旧 turn 回复拒绝/忽略，不把 peer 生命周期绑定为子委派。

## 持久化创建与暂停恢复

format3 中，原输入属于 Agent 事件；完整模型/工具请求属于中立 Actions Operation；有序来源与编排关联属于 Agent Storage；业务输出属于不可变 accepted Result。事件/checkpoint 不保存第二份 transcript。Reducer 只归约控制，Loader 固定序号验证，ContextBuilder 逐来源生成可丢弃原生消息，Core 不接收 Repo 或执行回调。

资源初始化是运维动作，不属于 Agent 启动，authority_id 必须是实际数据集 UUID。已有 Repo 与 Runtime 接线准备后：

```elixir
{:ok, durable} = Beamlet.Agent.Durable.open(repo, %{
  agent_id: agent_uuid, authority_id: dataset_uuid, command_id: command_uuid,
  definition: %{"version" => 1}
})
{:ok, durable} = Beamlet.Agent.Durable.with_runtime(durable, runtime)
# runtime 含 authority_repo、journal_repo、executor_id、executor_boot_id
{:ok, ref} = Beamlet.Agent.start(node(), id: agent_uuid, model: binding, durable: durable)
{:ok, turn} = Beamlet.Agent.input(ref, "你好", input_command_uuid)
```

稳定 command UUID 用于查回原响应；未知写入不会重新写入或发送。输入、prepare 与消费都先做纯归约 preflight，再提交事务，实时状态只应用已提交事件。工具批次原子准备，提交后才 dispatch；接受 Result 不推进 Agent seq，消费时才按 ordinal 提交引用/join。Runtime 再次检查精确 prepared 身份与当前限额，不能把持久化失败降级到内存执行。

`Durable.inspect(%{repo: repo, agent_id: uuid}, through_seq: seq)` 完全只读，不需绑定、provider、实时父级或 executor。Loader 最多 100000 事件/32 MiB，按 100 事件 keyset 页固定截止位；引用遍历有限 5 秒。缓存先校验完整历史前缀，前后缀共享预算；缺失/坏缓存回退历史，损坏历史、接受摘要或来源阻塞。缓存不能修复历史，也不是省掉前缀 I/O 的保证。

`Agent.restore(locator, expected_version, command_id)` 要在 authority 上调用，locator 可带 model/tools/catalogue/runtime。它先拒绝仍注册的身份，等旧本地发送者组实际 DOWN 后激活新 generation 并暂停，不调用模型/工具。缺实时绑定会使 Server 启动失败，已提交激活仍暂停。仅想读取应使用 inspect。

`Agent.continue(ref, expected_version, decision, command_id)` 显式记录决策并继续；旧版本返回 stale_version，旧 owner 未退休返回 owners_retiring 且不写决策。已接受结果可消费而不再执行；未声明发送的 prepared 工作可首次发送，claimed unresolved 不得再发，完成的恢复回到 idle 不调用模型。依赖改变拒绝 dependency_missing，后续兄弟保持 prepared。

不确定/cancelled/deadline/unknown 接受结果需决策 `%{"operation_id" => id, "resolution" => "confirmed_failed"}` 或 confirmed_executed；多项必须一次给 `%{"resolutions" => [decision, ...]}`。决策不能重标记明确 ok/error、覆盖 accepted Result 或重新授权 claimed unresolved；确定模型错误只消费一次并保留有来源的失败观察。

## 同 authority 引用分叉

```elixir
{:ok, fork} = Beamlet.Agent.fork(
  %{repo: repo, agent_id: source_uuid, source: %{environment: :confirmed_stopped}},
  through_seq, current_source_version, fork_command_uuid)
```

选定位必须已提交、无 pending/未消费工作或 blocker，处于安全 await_input、完整配对的 await_model_result 或 completed。注册源返回 source_not_frozen，本地发送者必须退休。写事务重检源 version/generation 与引用成员，PG 对源加共享锁；不修改源行。相同命令幂等，UUID 也是稳定子 Agent UUID，变化参数冲突。返回 agent_id/locator/version/generation/through_seq/source/risk。

子实例仅有 created/forked/context.inherited 三个初始事件，version/generation 为零，paused/await_input。直接有序来源与扁平闭包最多 128 sources/1024 refs。输入以不可变摘要去重 artifact 共享，保留原事件/Agent/序号；结果保留原 Operation 归属、描述/接受摘要与显式 resolution。不复制 pending、消费/命令去重、attempt、执行实体或 provider session。链式 fork 重放自己的事件和直接内容，不读父历史前缀；内容必须持续保留，无自动 GC 或跨数据集转移协议。继承 usage 是来源事实，不是新执行/账单。

默认即使父级 idle 也 risk=unconfirmed。read/export/restore 不授予执行；确认安全的子级用空 decision，未确认风险需显式 `%{"risk" => "accepted"}` 记录。source confirmed_stopped 也是运维断言，不证明远端已停止或回滚；旧回执不能推进子级或覆盖 accepted Result。

## 历史与离线导出

`Agent.history(locator, %{view: view}, cursor)` 支持 facts/turns/context/steps/tools/evidence/decisions/provenance。context 归约到 as_of_seq，facts/turns 游标含固定 through_seq/keyset 位，下一页原样传 next_cursor。steps/tools 只包含截止位已消费输出；evidence 标为独立 Operation snapshot，不假称 Agent-seq 接受时刻。来源列表提供因果关系，没有图 UI 或第二份可变 authority 图。

```elixir
{:ok, page} = Beamlet.Agent.history(locator, %{view: :facts, limit: 100})
{:ok, fixed} = Beamlet.Agent.TraceExport.begin(repo, locator)
{:ok, manifest} = Beamlet.Agent.TraceExport.write(fixed, dir: fresh_directory, page: 100)
{:ok, verified} = Beamlet.Agent.TraceExport.verify(fresh_directory)
```

begin 在写页前捕获 Agent 截止位、每 Operation 高水位及完整 request/accepted/evidence/input/definition/artifact 闭包，之后追加/接受/回执不改变包。format2 manifest 配 events/inputs/operations/definition JSONL 与二进制 artifacts，不依赖可选控制缓存；请求是正文而非冒充正文的哈希。

每文件 SHA-256 与计数及各内容/来源/回执摘要离线再检查；receipt 绑定捕获的 attempt/executor，继承来源保持原 owner，无需父事件。缺失/坏内容列入 missing，history_complete=false。drop_content 移除输入/请求/输出/定义/证据正文与全部 artifacts，逐行标记且不可恢复。输出目录必须为空，避免脱敏时残留旧明文。包/备份是敏感内容；哈希不防整包协同重写，无导入、执行或真实性授权。

捕获最多 32 MiB、1024 Operations、每 Operation 最多 32 条 receipt evidence、5 秒引用遍历；页为 1..500，page_bytes 为 4096..4 MiB，过页整记录标记而不截断。超量历史/闭包明确拒绝，不能称截断为完整。数据集 format3 与 trace format2 独立。

## 验证入口

从仓库根目录执行：

```sh
mix test apps/beamlet_agent/test --seed 631927
mix test --no-start apps/beamlet_agent/test/beamlet/core_adapter_test.exs apps/beamlet_agent/test/beamlet/context_read_order_test.exs
mix compile --warnings-as-errors
elixir scripts/quality/check-contracts.exs
```

默认 SQLite；隔离 PostgreSQL 验证使用 BEAMLET_AGENT_TEST_ADAPTER=postgres、BEAMLET_PG_SOCKET_DIR 和可选 BEAMLET_PG_PORT/BEAMLET_PG_USER，fixture 仅创建/删除自己的新数据库。Server durable-e2e 与 `scripts/deployment/durable-e2e.sh` 是实际模型→工具→模型、进程重启、暂停继续及 fork 的独立门槛；命名 peer、release、物理跨机、付费 provider 与断电验收不能由普通测试推断。
