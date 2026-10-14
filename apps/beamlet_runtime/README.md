# 本地 Runtime 与 SQLite Storage

`BeamletRuntime` 已提供静态 Handler 登记、Coordinator、持久扫描 Scheduler、Worker 会话和真实 SQLite Storage.
本地调用链为 Submit → 建立/领取 → 持久 Start Authorization → Handler invoke → Report Stored / Outcome → ReadFacts.
这是可信本地应用 API; Coordinator 配置是本地 capability, 不能从客户端消息构造或直接暴露为网络入口.
跨设备认证、ACL、wire codec 和真实第三方 Adapter 仍须分别实现验收.

## 本地执行

在 `apps/beamlet_runtime` 中运行 `iex -S mix`, 使用同步示例 `beamlet.echo.v1`:

```elixir
alias Beamlet.{Definition, Identity}
alias BeamletRuntime.{Coordinator, Scheduler, Worker}
alias BeamletRuntime.Handlers.Echo
alias BeamletRuntime.Storage.SQLite

path = Path.join(System.tmp_dir!(), "beamlet-local-#{Ecto.UUID.generate()}.db")
{:ok, _repo} = SQLite.start_link(database: path, name: BeamletRuntime.LocalRepo, pool_size: 2)
:ok = SQLite.migrate(BeamletRuntime.LocalRepo)
c = Coordinator.new(repo: BeamletRuntime.LocalRepo, collection: "local", actor: "local-runtime", handlers: [{Echo, %{}}])
{:ok, _worker} = Worker.start_link(name: BeamletRuntime.LocalWorker, id: "device-a", coordinator: c, environment: %{"echo" => true})
{:ok, _scheduler} = Scheduler.start_link(coordinator: c, workers: [BeamletRuntime.LocalWorker], interval: 100)
{:ok, identity} = Identity.new("local", "agent", "call-1")
{:ok, definition} = Definition.new(%{operation: "beamlet.echo.v1", input: %{"text" => "你好"}})
{:ok, submitted} = Coordinator.submit(c, identity, definition)
id = submitted.facts.intent.id
{:ok, facts} = Coordinator.read(c, id)
facts.intent.outcome
# 异步: 可以先返回 nil; 后续读取将得到 Succeeded / 原输入.
```

相同身份和定义复用原 Intent/Outcome, 即使兼容 Handler 暂时下线也不改变原接受事实.
Operation schema 校验只在保护内建立新 Intent 时执行; 重提交比较已存不可变原定义, 异定义仍拒绝.
无须发送唤醒消息; Scheduler 周期扫描持久候选, 分页并回绕重扫.
可使用 `Scheduler.scan_once(c, workers, cursor, limit)` 手动推进一页, 或 `tick/1` 请求启动一次后台扫描.
扫描与 Worker 可以重复/并发; 候选不授予权限, 所有领域变更仍由 Storage 重验.

部署时将 Repo、Worker 和 Scheduler 加入应用 supervision tree, migration 仍是显式步骤.
使用稳定的注册 Repo/Worker 名称让调用方在进程重启后找到新实例, 不保留已退出实例的 PID.
`BeamletRuntime.Application` 只自动启动外部调用/扫描的 Task Supervisor, 不默认创建数据库或启动某个设备 Worker.

## Worker 与恢复

- 每次 Worker 启动生成新的 UUID incarnation, 不读取旧 grant 为新会话调用许可.
- 已提交 grant 交付后, 先检查完整 scope/incarnation、原 binding、当前资源与重试条件, 再安装单次调用标记并派发 Task.
  Task 真正进入 Handler 前再次采样契约时间并核验资源, 而不只使用派发前的检查.
  期间条件失效则保守不调用, 不制造 Failure; 已安装的单次标记不清除.
  同一会话内按 collection/Intent/Execution 保留标记, 不因任务完成或 Stored 而清除; 默认容量 10,000, 耗尽拒绝新调用.
- grant 不要求 lease 继续存活. 取消/expiry 不是外部 fencing; 已持有许可的原会话仍可能调用.
  Worker 退出也不承诺停止已经派发的 Task 或外部请求; Task 不自动重启, 新 Worker 不继承其调用权限.
- 心跳只续租在途调用, 不逐条写 History. Pending 保存完成关联后可以释放 Worker; 查询/回调不依赖旧 Worker.
- Handler 异常、未知响应、非法结果 schema 或查询故障不转成 Failure. 只有明确、合格的 Failure 证据才能参加停止裁决.
- 报告使用稳定随机 ID. 未取得成功 Commit 则在当前会话保留并重投同一 Report, 不再次调用 Handler.
  Repo 暂停时返回存储错误; 配置的同名 Repo 恢复后可继续入账. Worker 同时崩溃且没有外部查询/重投时仍可能 Unknown.
- Scheduler 重验 expiry、查询原授权关联, 再评估已保存失败/安全替代. 不以 NotFound、超时或预算耗尽制造 Failed.
  替代、授权、调用分别检查原幂等保证, 新 Handler 的较长窗口不能延长原保证.

授权确认丢失: 原 incarnation 可以重取相同 token/binding; 扫描仍有效的 StartAuthorized 候选以驱动恢复.
报告确认丢失: 重投相同 Report; Stored 与 OutcomeAccepted 分别从 Commit.reply 和 facts.intent.outcome 读取.
回调先于 Pending: 原关联已在授权事务提交, 后来的 Pending 只留证据, 不回退 Resolved/Outcome.

## Handler 与可信入口

`BeamletRuntime.Handler` 定义兼容 Operation、实现发布身份、输入/结果 schema、资源 binding、invoke 和可选 query/callback.
`Registry` 只选择配置的模块; 持久 binding 通过确切 Handler 身份找原实现, 不从客户端字符串加载模块.
同一登记不能有重复发布身份. 没有兼容 Handler/资源时保持 Prepared; 旧 Pending/Unknown 缺 Adapter 时保留原事实.

`bind/4` 与 `validate_binding/4` 必须是有界本地检查, 无网络和外部副作用.
新授权经 `SQLite.checked_command/6` 在保护内读取原事实、采样时间、重新选择受信 Handler/资源、重验领域规则并提交.
候选还须通过原 Domain 授权守卫; 不合格的首个发布不挡住后面的合法发布. 纯候选试算不提交 History,
最终选择仍由 Storage 重验提交. 原授权重投不重新选择发布, expiry 拒绝仍保存失效屏障.
调用前在 SQL 之外再次核验实际资源和原授权契约. invoke/query/verify_callback 永不放进 SQL 事务.
`completion`/`query` 关联须可重启解释并在调用前保存; 凭据正文不进入 binding 或 History.

`Coordinator.query/3` 与 `callback/5` 先检查原授权 binding 的 query/completion 能力, 未声明则不运行 Adapter.
通过后调用原发布的 Adapter, 检查来源类型/目标 scope、Operation schema 和持久绑定后入账.
Adapter 必须先完成来源、账户、签名、事件身份与协议依据验证, 再形成 Report; NotExecuted 还需要真实的既往及未来排除保证.
关联不是凭据. 每次独立查询观察须有自己的稳定身份; 同身份改内容仍按冲突保留.
外部 Adapter 异常/非法回复不会取得 Stored 确认. Worker/Scheduler 对未知本地消息拒绝/忽略, status 不打印配置正文.

Echo 仅支持受限值同步返回及空硬约束, 资源为明确启用的本地纯计算能力; 不声明幂等、Pending、query 或 callback.
测试中的 HMAC/查询 Fixture 只用于入口和来源契约验证, 不是可部署的第三方协议.

## 持久审批示例

`Handlers.Approval` 接入本地 `human.approval.v1`, 不再只依靠测试 Fixture 展示 Pending.
`Approval.Store` 是独立资源服务, **不是新的 Beamlet Storage 后端**, 应使用与 Authority 不同的 SQLite 文件.
资源请求/决定与 Authority 的授权/报告是两个独立事务, 不伪装成跨数据库原子提交.

```elixir
alias BeamletRuntime.Approval.Store
alias BeamletRuntime.Handlers.Approval

{:ok, approval_repo} = Store.start_link(database: Path.join(System.tmp_dir!(), "approvals-#{Ecto.UUID.generate()}.db"), pool_size: 1)
{:ok, :ok} = Store.migrate(approval_repo, "local-approvals")
service = Store.new(approval_repo, "local-approvals")
# 使用前面示例的 Authority repo; Worker 环境与对应服务登记均为可信本地配置.
c = Coordinator.new(repo: BeamletRuntime.LocalRepo, collection: "local", actor: "local-runtime", handlers: [{Approval, %{service: service}}])
{:ok, worker} = Worker.start_link(id: "approval-worker", coordinator: c, environment: %{"approval_service" => service.identity})
{:ok, identity} = Identity.new("local", "agent", "approval-1")
{:ok, definition} = Definition.new(%{operation: "human.approval.v1", input: %{"service" => service.identity, "subject" => %{"text" => "请批准"}, "responders" => ["reviewer"]}})
{:ok, submitted} = Coordinator.submit(c, identity, definition)
id = submitted.facts.intent.id
{:ok, _page} = Scheduler.scan_once(c, [worker])
# 等 Store.read(service, "local", id) 确认请求已建立后, 受信本地应用提交已认证响应者的选择:
{:ok, receipt} = Store.decide(service, "local", id, "reviewer", "denied")
{:ok, _page} = Scheduler.scan_once(c, [worker])
{:ok, facts} = Coordinator.read(c, id)
facts.intent.outcome.value
# %{"decision" => "denied", "approval_ref" => id, "decision_ref" => receipt.decision_ref}
```

- 输入固定服务、受限值 subject 和非空且无重复的 responders 列表; 硬约束仅支持空 map, 不猜测默认账户/响应者.
- 授权前保存原 collection/Intent 关联、资源实例和幂等 scope/key; 所有尝试使用同一个资源请求键.
- 服务数据库持久保存 identity 与随机 instance. 重启原库保留 instance; 同名新空库不能继承旧 binding/幂等保证.
  该标识不提供备份回滚检测或克隆库 fencing, 不支持自动 Authority/资源迁移.
- `create` 原子 create-or-get, 同键不同请求拒绝; 请求、决定和 receipt 不设 TTL, 没有删除/覆盖接口.
- `decide` 按原 responder 列表检查权限, 第一个通过事务的选择保存唯一决定与稳定 receipt.
  同响应者同选择重投返回原 receipt, 改选择或改响应者拒绝. `approved`/`denied` 都是 Success, 不是引擎控制面的人工协调.
- query 使用配置的本地 Repo capability 核验原资源实例与请求. 没有请求或尚未决定都仅为 NotFound 观察,
  从不宣称 NotExecuted. 缺失、等待、确定决定使用不同稳定观察身份; 重复查询不重复 History.
- 创建响应丢失可查询原请求; Worker/Coordinator/资源 Repo 重启后继续原等待, 不重建审批.
  服务不可用或 mismatch 返回不确定/拒绝, 不制造 Failure. 逻辑取消不删除或停止资源审批, 迟到决定仍可留证据.
- `decide` 的 principal 必须由调用它的本地应用认证. 这里没有 HTTP、公共 webhook、签名协议或用户登录功能;
  向网络开放前必须增加真正的 Transport/ACL. Store.query 的可信来源是本地受控数据库, 不接受原始客户端 Report.

这些保证依赖保存同一资源库及其 receipt. 数据库永久丢失、旧备份恢复、文件系统掉电和跨服务替换仍需独立协议,
不以本地示例宣称任意第三方审批支持幂等或恰好一次创建.

## SQLite 事务与结果

写命令使用 `BEGIN IMMEDIATE`, 保护内加载当前快照, 在同一 SQL statement 中从 SQLite VFS 时间采样整数 epoch 毫秒.
随后重验登记/资源和领域守卫, 保存快照/报告/唯一 Outcome/History, commit 后才返回 `Storage.Commit`.
调用方不能通过 `mode` 选项把写事务改成 deferred. SQL 不包含外部调用或网络等待.

- `{:ok, %Commit{facts: %Facts{intent: intent, revision: revision}, reply: reply, events: events}}`: 已提交决定.
- `{:error, reason_atom}`: 明确领域拒绝; 不产生待提交变化.
- `{:error, %Storage.Error{kind: :busy_exhausted | :unavailable | :indeterminate, cause: diagnostic}}`: 存储故障,
  不能转为 Failed.

到期拒绝可以成功提交: `Commit.reply` 为 `{:rejected, :lease_expired}`, events 含持久失效屏障.
状态变化才增加 storage revision; 相同报告/领取/授权重投不增加 revision 或 History.
普通续租可以增加 storage revision 而不增加领域 History; storage revision 不是协调/治理 judgment revision.

仅确认尚未进入事务的 busy BEGIN 失败会有界重试, 默认最多再尝试两次.
事务进入后的 SQL/连接故障保守返回 Indeterminate, 即使某些故障实际上已经回滚.
调用方按原提交身份, token 或报告身份读取/重投; commit 响应丢失不能触发外部重调用.

数据库设置固定为 WAL, `synchronous=FULL`, `foreign_keys=ON`.
同身份建立和 Outcome 唯一由复合 SQL 约束保护; 不使用单个 GenServer 串行化领域命令.
两个独立 Repo/pool 访问同一文件也经过相同 SQL 保护. SQLite 的写入仍然是数据库级串行.

## 最小使用

在 `apps/beamlet_runtime` 中运行 `iex -S mix`:

```elixir
alias Beamlet.{Definition, Identity}
alias BeamletRuntime.Storage.SQLite

path = Path.join(System.tmp_dir!(), "beamlet-example-#{Ecto.UUID.generate()}.sqlite3")
{:ok, repo} = SQLite.start_link(database: path, pool_size: 2)
:ok = SQLite.migrate(repo)
{:ok, identity} = Identity.new("local", "agent", "call-1")
{:ok, definition} = Definition.new(%{operation: "api.request.v1", input: %{"prompt" => "hello"}})
{:ok, submitted} = SQLite.submit(repo, identity, definition, "trusted-authority")
id = submitted.facts.intent.id
{:ok, prepared} = SQLite.command(repo, "local", id, {:create_execution, "execution-1"}, "trusted-authority")
{:ok, facts} = SQLite.read(repo, "local", id)
{:ok, history} = SQLite.history(repo, "local", id, facts.revision)
facts.intent == prepared.facts.intent
# true
```

应用可将 `{SQLite, database: path, name: repo_name}` 加入 supervision tree; schema migration 是显式部署步骤.
默认不启动数据库或创建生产数据文件. `migrate/1` 只执行当前 v1 建库迁移, 不承诺已有旧版数据的自动兼容.

## 读取, 扫描与格式

`read/3` 在只读事务内返回一个一致快照, 包含原定义, 全部执行/报告/绑定与 Outcome.
当前内部 JSON codec v1 限制每份快照最多 16 MiB, 超出返回容量拒绝, 不制造业务失败.
codec 用明确标签和固定模块/atom 白名单保存领域结构, 不使用 Erlang term 反序列化或动态 atom 创建.
逻辑正文中的同名标签仍是普通用户数据; wire JSON 的重复 key/数值词法校验另由 Transport 实现.

`history/6` 按 `read/3` 的 revision 固定审计范围, cursor 为 `{revision, position}`, 默认每页 100 条, 上限 1,000 条;
`next: nil` 表示范围读取完毕. 晚到报告不会改变旧范围内的审计材料. `discover/4` 返回尚无 Execution 的 Open Intent, 以及
Prepared/StartAuthorized/Waiting/Unknown/Resolved 当前尝试的候选, 默认上限 100, 最大 1,000. StartAuthorized
包含未到期记录以恢复丢失 grant 回复; Resolved 包含等待停止/安全重试评估的已知失败. 候选不授予许可; 调用方须定期从头重扫,
并通过领域命令重验条件.

有限幂等需要可信 `contract_clock: fn -> resource_protocol_time end`, 在锁取得后采样.
该函数只能读取已核验的有界本地契约时钟, 不得访问网络或直接采用客户端时间.
未提供时按没有可重验的有限保证处理. 本实现不声称 SQLite 墙钟等于资源时间;
外部协议仍须保证延迟到达的过期 key 不重新产生效果.

## 验证边界

运行 `mix test --warnings-as-errors` 或在根目录运行完整 umbrella 测试.
SQL 测试使用真实临时文件, 覆盖独立 Repo 并发提交, 领取竞争, 原 grant/报告重投,
快照/报告/Outcome/History 原子回滚, 取消与完成竞争, 锁等待跨 expiry, busy 重试耗尽,
History 分页一致性, 回调完成和停止/重启 Repo 后的恢复. codec 另检查标签混淆和 64-bit 精确往返.

另外 44 个本地执行测试覆盖完整 Echo 调用链, 并发派发, Coordinator 竞争, 丢失 grant 回复,
Worker 新 incarnation, Prepared 重领, 在途 Worker 崩溃/原查询恢复, Pending/早到回调, 假签名/错误 schema,
原幂等窗口调用前过期, 取消后/expiry 后原许可调用, SQL 报告重投, Repo 离线/恢复与扫描进程重启.

另有 17 个审批测试使用 Authority/资源两个真实数据库, 覆盖 approve/deny 正常完成、未授权响应、不可变 receipt,
创建响应丢失、早到完成、Worker/资源重启、独立 Repo 并发建立/决定、安全替代重用原审批、原 scope 与实例绑定.
共享 Worker 的不同 Intent 故意复用局部 Execution ID, 验证许可/标记/报告隔离及原 key 的独立结果重建.

Repo 停止/重启与丢弃已提交回复不等于真实掉电或 commit 网络断连测试.
文件系统/磁盘掉电保证, 更细故障分类, PostgreSQL 符合性, 远端权限/认证与真实 provider 条件仍需后续验收.
模型与代码对应关系见 [对照记录](../../model/implementation-conformance.md).
