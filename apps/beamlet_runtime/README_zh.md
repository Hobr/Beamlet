# Beamlet Runtime：一次尝试的执行

[English](README.md) · [Agent](../beamlet_agent/README_zh.md) · [Node](../beamlet_node/README_zh.md)

Runtime 拥有 Operation 的发现、选择、准入、执行、进度与唯一终态投递，默认只保留内存状态。它不解释模型 provider，也不拥有 Agent 的上下文或结果消费。直接依赖 Actions、通用 Storage、Actions Storage 和 Ecto；使用 OTP Logger/Crypto，不依赖 Agent。

在仓库根目录进入 `nix develop`（OTP 29 / Elixir 1.20），首次运行 `mix deps.get`、`mix compile`。库没有 Application 回调；宿主必须在监督树中安装 `{Beamlet.Runtime, options}`，每 VM 一棵。默认 `execution: false` 只启动共享发现、Directory、临时协调器和 endpoint；显式 `execution: true` 才增加 Workers/Gateway。共享与执行监督岛分别采用 one_for_all；基础设施重启使实时 Ref 失效，不重建业务任务。

## 内存调用示例

以下可在根目录 `iex -S mix` 中执行，前提是当前 VM 尚未启动 Runtime/Node；示例无外部服务副作用：

```elixir
defmodule LocalEcho do
  @behaviour Beamlet.Actions.Handler
  def run(payload, _context), do: {:ok, payload}
end

{:ok, runtime} = Supervisor.start_link([
  {Beamlet.Runtime, execution: true, handlers: %{"echo" => {LocalEcho, %{}}}}
], strategy: :one_for_one)
{:ok, operation} = Beamlet.Actions.Operation.new(kind: "echo", payload: %{"text" => "你好"})
{:ok, ref} = Beamlet.Runtime.submit(operation, owner: self(), sink: self())
```

Directory 异步收到报告之后才有可选目标；启动树成功不等于已收到就绪报告。可用 `Beamlet.Runtime.observation/0` 查看报告，再进行一次提交。若示例恰逢报告尚未到达，终态可为 `:no_target`，不能把失败自动重试当作协议。完整调用者按同一个 Ref 接收：

```elixir
receive do
  {:beamlet_operation, ^ref, {:progress, _attempt_id, sequence, _value}} ->
    Beamlet.Runtime.ack(ref, sequence)
  {:beamlet_operation, ^ref, {:result, result}} ->
    result
end
{:ok, status} = Beamlet.Runtime.status(ref)
```

该片段只处理一条消息，真实消费者应持续处理至终态并按需设置自己的有限等待。`submit/2` 返回 `{:ok, ref}` 只表示协调器存在，未必已准入；即时错误包括 invalid_operation/unavailable/capacity。owner/sink 默认调用者，`require_live_owner: true` 只接受本地 owner，并在阻塞读取之后重新检查存活。基础设施调用仍可能等待，不能把监控等同于实时中断所有阻塞调用。

`cancel(ref)` 的 `:ok` 只确认处理停止请求。必须继续观察终态；没有观察退出时仍为 `uncertain/cancel_unconfirmed` 或 `deadline/termination_unconfirmed`。Gateway 首个处理的 cancel/deadline 决定已观察停止的来源；无关崩溃是 error/worker_lost，抢先接受的成功仍为成功。本地 worker 的 DOWN 不证明外部请求停止、账单停止或副作用回滚。

进度完整信封受字节、总量、速率和额度限制，默认每 sink 16 个未确认序号；消费后 ack 释放额度。终态不依赖额度，丢弃事实出现在终态元数据。Handler 自行拥有其额外进程与外部资源。默认协调器连同保留终态最多 256，保留 30 秒后 status 返回 unavailable。默认 Operation 262144 字节、Result 1048576 字节、progress 8192 字节；凭证计入完整线缆预算，只经独立 credentials 传递，不进入正常报告或持久化描述。

## 选择、容量与观察

选择检查报告新鲜度、协议/kind、能力、环境、允许节点及全部 claims，再按利用率和节点/代际排序。发现不预留容量，Gateway 重新验证并原子扣减本地池，因此报告上的可用容量只是建议。成功 Result 也不意味着 Directory 已收到新容量报告。lease 只用签发 Gateway 的本地时钟计算，并保守减少剩余预算；不能跨 VM 相减单调时间。

`observation/0` 最多返回 256 个报告及 1000000 字节完整响应，5 秒有限读取。age 是本 VM 接收年龄；fresh/stale/not_reported 不等价于服务健康或节点死亡。数量溢出令 complete=false，字节溢出返回 limit；不暴露租约、私有设置或凭证。

## 显式持久化

选用 `Beamlet.Actions.Storage.Profiles.authority/0` 与 `journal/0`，通过 `Beamlet.Storage.Dataset.initialize/2` 显式安装新数据集；已有数据集按同一 descriptor 打开，open 不迁移。可用 Actions Storage 的 SQLiteAuthorityRepo、PostgresAuthorityRepo、ExecutorJournalRepo；authority/journal 必须独立，SQLite 各自指定隔离的 peer_database。加载库不会启动 Repo。

```elixir
persistence = Beamlet.Runtime.Persistence.new(
  authority_repo: authority_repo, journal_repo: journal_repo,
  authority_id: authority_id, executor_id: executor_id,
  executor_boot_id: executor_boot_id,
  dispatch_scope_id: nil, dispatch_epoch: nil)
{:ok, ref} = Beamlet.Runtime.submit(operation,
  persistence: persistence, owner: self(), sink: self())
```

这些变量由可信宿主在打开资源后提供；Gateway 也必须配置匹配接线。scope UUID/非负 epoch 必须成对，默认都为 nil；它们是中立 dispatch 栅栏，不是 Agent 身份或授权元数据。owner PID 是瞬时生命周期监控，不是持久化 owner 字段。无效 Persistence 接线抛出异常。

调用者如需在自身事务中原子准备，使用 Actions `OperationRecords.prepare_in_transaction/2`，参与者失败必须回滚外层同 Repo 事务；独立 `prepare/2` 自行回滚。提交后把响应作为 Runtime `prepared:` 传入，不再准备另一个请求。响应含字符串键 operation_id、attempt_id、description_digest、attempt_version、lock_version、dispatch_state、dispatch_scope_id、dispatch_epoch。Runtime 对比完整不可变描述、scope、摘要、两个版本、精确尝试、executor/boot、prepared 状态及无接受结果；修改请求或替换尝试会在发送前失败。

固定描述包含 kind、协议、payload、budget、claims 与 safety（metadata/capabilities/environment/allowed_nodes）。逻辑参数必须在准备前固定；credentials 是瞬时覆盖，线缆计数但不入库。

协调器先提交 prepared → send_claimed 再发送。PG 先对 scope 加 FOR SHARE 再对 Operation 加 FOR UPDATE；rotation 对 scope 加 FOR UPDATE，SQLite immediate 写事务串行化。rotation 先提交会以 stale_epoch 拒绝旧 pending，claim 先提交则保留 claimed 语义；rotation 无法撤回网络发送。显式 pending continuation 可调用 DispatchScopes.reauthorize_in_transaction/2，但不能重授权 claimed/accepted，返回的新版本必须替换旧绑定。

执行器先提交 journal start_intent 再启动 worker；终态附件/回执提交后才完成通知，authority 先提交证据及唯一 accepted Result 再通知 sink。未知提交不授权重发；接受失败在 status.durable 显示 accepted=false/accept_error，result 不可见。重启将遗留 start_intent 标为 unknown_after_restart，不重建 worker，不恢复旧容量，不表示从未执行。迟到证据可保留但不替换 accepted Result；没有自动业务重试或 exactly-once 保证。

`Runtime.evidence(persistence, operation_id, attempt_id)` 只读并校验尝试绑定，返回 authority 与 journal 行（或 :not_found/:unavailable）。缺失与不可读均不足以断言未执行。编排消费仍属于嵌入调用者。

## 验证入口

从仓库根目录运行：

```sh
mix test apps/beamlet_runtime/test --seed 631927
mix format --check-formatted apps/beamlet_runtime/lib/beamlet/runtime.ex apps/beamlet_runtime/lib/beamlet/runtime/*.ex
mix compile --warnings-as-errors
elixir scripts/quality/check-contracts.exs
```

分布式测试需按测试标签另行以命名节点执行；普通本机测试不证明物理跨机、真实 provider 或断电恢复。
