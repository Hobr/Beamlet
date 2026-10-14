# 重复风险策略与资源侧 fencing

本轮补齐 Quint `repeatAllowed`、`fenced` 的本地能力，并移除重试路径上额外的全局冲突限制。
Domain 仍保持纯函数；资源事务与 Authority SQL 分别提交，原报告、历史冲突和已接受 Outcome 保留。

## 显式接受重复风险

创建不可变 Definition 时，可明确指定：

```elixir
{:ok, definition} = Beamlet.Definition.new(%{
  operation: "your.operation.v1",
  input: %{"request" => "original"},
  policy: :retry_once,
  repeat_accepted: true
})
```

`repeat_accepted` 默认 false，必须为布尔值，是原 Definition 身份的一部分。
已接受 Identity 不能通过重投把 false 改成 true；需要新的业务提交身份。
该字段对应模型的 ALLOW_REPEAT 配置在单个 Intent 上的显式工程表示。
它不增加 RetryOnce 两次建立预算，不自动开启 StopOnFailure 的重试，不放宽资源/账户/硬约束检查。

恢复优先选择未授权或当前有效 NotExecuted；否则明确接受风险时保存
`replacement.basis == :repeat_accepted`，不再依赖旧幂等窗口或同一幂等协议仍有效。
这个依据在授权和实际调用前再次核对原 Definition。接受风险可能导致两次外部效果，
不是未执行证明，也不会自动关闭 Unknown、排除旧成功或解除终结时的冲突。

冲突本身不再一律阻止替代和后续调用：有合格恢复理由及未授权、NotExecuted、幂等保证或风险接受即可。
普通成功/失败终结及协调采用仍执行各自的冲突、证据、旧成功与未知风险守卫。
迟到结果和历史冲突继续保存；不能把“允许重试”解释为“允许忽略矛盾并接受 Outcome”。

## 独立 fenced-object Operation

`BeamletRuntime.Handlers.FencedObject` 提供 `object.fenced_replace_if_version.v1`。
请求与业务 Success 形状复用[共享对象 CAS](OBJECTS.md)，但 Operation、Handler、invoke/query/fencing
协议身份独立；原 `object.replace_if_version.v1` 的 binding 不获得新能力。

新 binding 保存原服务 instance/account/object、query 关联以及非空 `fencing` 能力。
它不声明 idempotency：在默认拒绝重复风险的情况下，只有可靠排除证明才能支持已授权尝试的替代。
资源仍保存 Intent-local 完整请求 receipt，避免正常回执恢复改变原业务结果。

`Coordinator.fence(c, intent_id, execution_id)`：

1. 读取已提交原授权，核对保存的 fencing 能力并解析原 Handler。
2. 在 Authority SQL 之外调用 Handler/resource，资源以 immediate 事务仲裁 invoke 与 fence。
3. 将原关联的 query Report 按正常报告路径原子保存；资源提交不等于报告已 Stored。

资源排除主键包含 service instance、account/object/operation/collection/Intent，以及 Execution ID。
记录完整原请求、完整授权 token 和永久 evidence_ref；同一 Intent 的后续尝试必须沿用原请求。
已用 Execution 的换 token、换请求拒绝；新 Execution 不受旧排除记录阻止。

| 资源事务先后 | 返回与后续行为 |
| --- | --- |
| 排除先提交 | 保存 NotExecuted 证明；该原授权未来 invoke 被资源拒绝，不写对象、不产生业务 receipt |
| invoke 先提交 | 返回原 Success receipt；不得再生成 NotExecuted |
| 排除回复丢失或 Authority 报告提交失败 | 原 query 可重读相同证明；旧 grant 已被资源阻止，Authority 可能暂仍 Unknown |
| 资源 SQL 失败 | 返回不确定/错误；不得制造排除证明或 Failed，可按原身份恢复 |

query 先读取该 Execution 的原排除证明，再读原请求 receipt；都没有则只有 NotFound。
新尝试写入成功后，旧尝试的原排除证明仍原样返回，不被新 receipt 覆盖。
NotExecuted Report 携带 `%Beamlet.Exclusion{authorization, query_binding, evidence_ref}`，
精确绑定原授权和原 query，不能由客户端的布尔断言构造。

取消、lease 到期或 Worker 退出本身仍不 fencing；只有资源已提交的永久排除记录提供这个保证。
该 Handler 不提供 Pending/callback。Scheduler 不擅自建立排除：可信应用明确调用 fence，
之后正常 query/recover 或 Scheduler 可消费已提交证明继续恢复。

## 存储与信任边界

对象库执行 `Store.migrate(repo, identity)` 升到 schema v2，新增不可更新/删除的 `object_fences`，
不重建旧对象/receipt，也不改变 service instance。新服务与旧服务混合运行不受支持。
Authority 内部 Codec 写 v3、读取 v1/v2/v3：旧 Definition 缺少 repeat_accepted 时仅导入 false；
v3 缺字段、非布尔接受值拒绝。v1 Intent 继续导入零判断版本基线。
这是存储读取兼容，不是旧/新程序混写或降级保证。

所有 facade、Repo 与 Handler 配置都是可信本地能力，token 不是远端凭据。
完整远端授权、第三方 Provider fencing、克隆隔离、备份回滚检测、PostgreSQL、真实掉电验收仍需独立实现。
保证依赖资源历史不丢失、不回滚、不被管理员修改；同名新库不能继承旧 binding，但相同 instance 的克隆仍未隔离。

## 可运行示例

在仓库根目录的 `iex -S mix` 中执行。这里直接调用 Handler 展示资源排除边界；
正式 Worker 仍须执行自己的 incarnation、已提交 Grant 核验和单次调用标记。

```elixir
alias Beamlet.{Definition, Identity}
alias BeamletRuntime.Coordinator
alias BeamletRuntime.Handlers.FencedObject
alias BeamletRuntime.Object.Store
alias BeamletRuntime.Storage.SQLite

directory = Path.join(System.tmp_dir!(), "beamlet-fencing-example-#{Ecto.UUID.generate()}")
{:ok, authority} = SQLite.start_link(database: Path.join(directory, "authority.db"), pool_size: 1)
:ok = SQLite.migrate(authority)
{:ok, resource} = Store.start_link(database: Path.join(directory, "objects.db"), pool_size: 1)
{:ok, :ok} = Store.migrate(resource, "objects")
service = Store.new(resource, "objects", "account")
{:ok, _} = Store.create_object(service, "shared", "initial")
c = Coordinator.new(repo: authority, collection: "local", actor: "local-app",
  handlers: [{FencedObject, %{service: service}}], ttl: 60_000)
{:ok, identity} = Identity.new("local", "agent", "call")
{:ok, definition} = Definition.new(%{operation: "object.fenced_replace_if_version.v1",
  input: %{"service" => "objects", "account" => "account", "object" => "shared",
    "expected_version" => 0, "content" => "new"}, policy: :retry_once})
{:ok, submitted} = Coordinator.submit(c, identity, definition)
id = submitted.facts.intent.id

authorize = fn ->
  {:ok, prepared} = Coordinator.prepare(c, id)
  execution = prepared.facts.intent.current_execution_id
  {:ok, %{reply: {:claimed, token}}} = Coordinator.claim(c, id, execution, "worker", Ecto.UUID.generate(), 0)
  {:ok, committed} = Coordinator.authorize(c, token,
    %{"object_service" => "objects", "object_account" => "account"})
  {:ok, grant} = Coordinator.grant(committed)
  grant
end
old = authorize.()
{:ok, _excluded} = Coordinator.fence(c, id, old.token.execution_id)
{:uncertain, :object_execution_fenced} = FencedObject.invoke(old, %{service: service})
{:ok, _replacement} = Coordinator.recover(c, id)
next = authorize.()
{:success, body} = FencedObject.invoke(next, %{service: service})
{:ok, completed} = Coordinator.query(c, id, next.token.execution_id)
true = completed.facts.intent.outcome.value == body
{:ok, %{"version" => 1, "content" => "new"}} = Store.read_object(service, "shared")
Supervisor.stop(resource)
Supervisor.stop(authority)
File.rm_rf!(directory)
```

## 验收范围

新增 3 项领域、11 项 fenced-object、1 项 Runtime 风险恢复与1项 Codec 兼容验收。
含独立 SQL 连接竞争、资源/Authority 两侧只读故障、INSERT 回滚、双库重启、重复证明、
替换资源/授权/请求拒绝、取消保留及旧库读取默认拒绝重复风险。

`check_domain_conformance.exs` 现在对照 2,000 组报告、1,568 组严格重试、1,568 组风险接受重试；
每类重试包括原 896 组以及 672 组带冲突组合。
`mix run scripts/check_resource_conformance.exs` 在真实文件库上重放两条完整选定轨迹，共 30 个检查点，
比较既有 Quint 的 phase/current、Knowledge、判断 revision、报告数、冲突、Outcome，以及资源版本/排除记录。
资源瞬时同步调用在该检查中按已提交业务结果投影，不验证内部 IO 的全部交错。
本轮完整 umbrella 310 个测试/文档测试通过，新增验收以 seed=1/42 重跑通过；
Quint fencedTests 2、strictTests 23、repeatingTests 79 场景以 seed=42/max-samples=1/Rust 重跑通过。
编译、严格 Credo、格式/diff、18 个变更 Elixir 文件的主动 LSP 与本文 fencing 示例执行通过。
这些验收不穷尽任意并发、Caller/Continuation 全部轨迹，不构成无界 refinement 证明。
