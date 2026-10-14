# 本地 CAS 对象与持久 receipt

`BeamletRuntime.Object.Store` 是独立外部资源数据库，
`BeamletRuntime.Handlers.SharedObject` 将它接入 `object.replace_if_version.v1`。
对应 [Quint 共享资源模型](../../model/quint/contracts/shared.qnt) 的版本竞争和原请求 receipt 恢复。

这是数据库中的逻辑对象，不操作普通文件路径，也不声明真实文件系统具有原子 CAS + receipt。
SPEC 的 `file.replace_if_version.v1` 是资源契约参考；这里使用独立 Operation Identity，
输入直接包含受限逻辑值 content，不冒充文件摘要、blob 保留或 volume 协议。

## 资源事务与结果

资源服务持久保存 identity/instance；同一数据库可有多个显式 account/object。
初始化只通过 `create_object` create-or-get，保存初始内容，版本从 0 开始。
已有同初始内容的对象返回当前版本/内容，不复位；改变初始内容拒绝。

一次 replace 的 immediate 事务：

1. 检查服务实例和受控 account；按原 key 查询 receipt。
2. 已有 receipt 且请求完全相同，返回原结果；同 key 不同 expected/content 等请求字段拒绝。
3. 无 receipt 时检查当前对象版本；相等则写新内容并递增版本，否则不写。
4. 同事务保存原请求、applied、决定时的版本和稳定 receipt_ref，提交后返回。

内容写入和 receipt 不存在跨事务窗口。测试通过 receipt INSERT 故障验证更新回滚。
资源提交与 Authority 接受 Outcome **分别提交**，资源已写不等于 Intent 已完成。

输入精确字段：

```elixir
%{
  "service" => "object-service",
  "account" => "account",
  "object" => "shared",
  "expected_version" => 0,
  "content" => %{"message" => "new"}
}
```

仅支持空硬约束。版本为受限值范围内的非负整数，最大 9,007,199,254,740,991；
匹配最大版本时拒绝继续写入，不溢出或复用版本。
content 是受限值 v1，整体请求受同一大小/深度/节点预算限制。

两种业务结果都为 **Success**：

```elixir
%{"applied" => true, "object_ref" => "shared", "version" => 1, "receipt_ref" => "..."}
%{"applied" => false, "object_ref" => "shared", "version" => 1,
  "receipt_ref" => "...", "reason" => "version_mismatch"}
```

Mismatch receipt 同样永久保留。后来对象版本变成 2，重投仍返回决定时的原版本 1，
不会重新判断并抢写别人已经更新的内容。对象缺失、资源离线/数据库故障返回不确定或错误，
不形成 Failure，也不自动初始化目标对象。

## Identity、授权与恢复

资源去重身份为：

`{service instance, account, object, operation, authority collection, intent_id}`

service instance 隐含在资源数据库，其他字段进入主键及持久授权 scope。
原 key 用 Intent ID，不用 Execution/incarnation；安全替代继续复用同一 key。
同一局部 key 在明确不同 collection/account/object 的 scope 中是独立请求。
不同 Intent 写同一版本由 CAS 仲裁，不会通过 Intent 幂等自动合并业务操作。

授权 binding 保存服务 identity/instance、account/object、协议版本、原 key/scope 和 query 关联。
Worker 环境须匹配 `object_service` / `object_account`；调用前重验原 binding，
资源事务再次核对实际实例。bind/validate_binding 为有界本地检查，不查询资源数据库；
真正的对象存在性和版本判定在资源事务发生。

该操作支持同步 invoke 和 receipt query，不声明 Pending、callback、NotExecuted 或停止能力。
资源查询是受控本地 Repo capability，不是远端认证/ACL。
`Store.new(repo, identity, account)` 只能交给可信应用代码，account 字符串本身不是凭据。

query 验证原完整 binding 与原请求，形成稳定的 receipt_ref Report ID：
重复读取不追加相同证据；合法迟到结果可保存，但不覆盖既有 Outcome。
receipt 缺失只返回稳定 `missing` NotFound，不能排除已授权旧 Worker 今后调用。
当前对象的 content/version，甚至内容恰好相同，都不替代原请求 receipt。

原调用成功后响应丢失、Worker 退出或 Authority 重启时，可通过原 query 恢复 Outcome。
如果独立安全依据允许替代，重投原请求读取原 receipt，不再次写入。
取消不阻止原 grant 持有者随后调用资源；迟到查询保留证据而不改写 Cancelled。

## Interface

| 操作 | 行为 |
| --- | --- |
| `start_link(database: path, ...)` / `migrate(repo, identity)` | 显式启动独立持久资源库与 schema v1；拒绝空路径和 :memory: |
| `new(repo, identity, account)` | 校验已初始化服务，读持久 instance，形成可信本地资源能力 |
| `create_object(service, object, initial_content)` | 原子建立或读取；相同初始化重投不复位版本 |
| `read_object(service, object)` | 读取当前内容/版本，用于业务观察，不充当某次请求的完成证据 |
| `replace(service, collection, intent_id, request)` | 原子 CAS + 请求绑定 receipt；同 scope/key 异请求拒绝 |
| `read_receipt(service, collection, intent_id, original_request)` | 按原请求读取完整不可变 receipt，不执行 CAS |

`replace/read_receipt` 返回 `{:ok, %{request: original_request, body: result}}` 或错误。
SQL 错误可能为 `:object_commit_indeterminate`：不能据此断言未写入，须按原身份查 receipt/重试。
没有全局锁持有者、无内存权威、无清理/删除/reset API。SQL trigger 拒绝 receipt 更新/删除。
拥有数据库管理员权限的代码仍属于可信部署前提。

## Runtime 示例

在 umbrella 的 `iex -S mix` 中使用三个显式启动的进程：

```elixir
alias Beamlet.{Definition, Identity}
alias BeamletRuntime.{Coordinator, Scheduler, Worker}
alias BeamletRuntime.Handlers.SharedObject
alias BeamletRuntime.Object.Store
alias BeamletRuntime.Storage.SQLite

{:ok, authority} = SQLite.start_link(database: "/tmp/beamlet-cas-authority.db", pool_size: 1)
:ok = SQLite.migrate(authority)
{:ok, resource} = Store.start_link(database: "/tmp/beamlet-cas-resource.db", pool_size: 1)
{:ok, :ok} = Store.migrate(resource, "object-service")
service = Store.new(resource, "object-service", "account")
{:ok, _object} = Store.create_object(service, "shared", "initial")

c = Coordinator.new(repo: authority, collection: "local", actor: "trusted-local",
  handlers: [{SharedObject, %{service: service}}])
{:ok, worker} = Worker.start_link(coordinator: c, id: "worker-1",
  environment: %{"object_service" => "object-service", "object_account" => "account"})

ids = for {key, content} <- [{"a", "first"}, {"b", "second"}] do
  {:ok, identity} = Identity.new("local", "agent", key)
  {:ok, definition} = Definition.new(%{operation: "object.replace_if_version.v1",
    input: %{"service" => "object-service", "account" => "account", "object" => "shared",
      "expected_version" => 0, "content" => content}})
  {:ok, submitted} = Coordinator.submit(c, identity, definition)
  submitted.facts.intent.id
end
{:ok, _page} = Scheduler.scan_once(c, [worker])

# 异步提交；后续重读直到两个 Outcome 都存在。
for id <- ids do
  {:ok, facts} = Coordinator.read(c, id)
  facts.intent.outcome
end
Store.read_object(service, "shared")
```

保留同一 Authority 与资源数据库，再次 submit 原 identity/definition 会复用原 Intent/Outcome。
不要用新空库代替原资源库：即使 identity 相同，新 instance 也不能接续已保存授权/查询。
`BeamletRuntime.Application` 不自动启动资源服务，生产应用须显式配置 supervision 和迁移。

## 证明前提与验收

无期限幂等依赖同一非回滚资源数据库持续保留全部 request/receipt。
instance 防止误接同名新库，不解决数据库克隆、旧备份恢复、Authority 历史丢失或管理员篡改。
WAL/FULL 是持久配置，不等于真实掉电验收。无远端协议、签名、第三方保留期、混合版本迁移或 PostgreSQL 支持。
版本多于模型固定的初始竞争例子是工程扩展，不能声称模型已证明任意更新历史。

18 项真实 SQLite 集成测试覆盖 Runtime 正常闭环、CAS 竞争、独立 Repo 并发/重复 key、
receipt 插入失败回滚、实际只读故障、回复丢失、Worker/Authority/资源重启、
安全替代、旧 grant/取消、缺 receipt 不推断、scope/实例替换、不可变历史和版本耗尽。
`mix test test/beamlet_runtime/shared_object_test.exs --warnings-as-errors` 在本应用目录运行。

这份资源协议提供模型假设的一个具体本地实现，不是 Runtime/SQL 的无界 refinement 证明，
也不把它推广成所有文件/API/Browser 的 exactly-once。
