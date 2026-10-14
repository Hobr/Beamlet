# SQLite Storage

`BeamletRuntime.Storage.SQLite` 将 `Beamlet.Domain` 的决定提交到真实 SQLite 文件.
这是内部可信 Adapter API; Runtime 须在调用前认证 principal, 检查当前权限, 核验 Handler 登记和报告来源.
本批尚未提供 Worker/Coordinator 调度循环, 外部 Handler, 验签入口或 Transport.

## 事务与结果

写命令使用 `BEGIN IMMEDIATE`, 锁取得后在同一 SQL statement 中从 SQLite VFS 时间采样整数 epoch 毫秒.
随后加载当前快照, 重验领域守卫, 保存快照/报告/唯一 Outcome/History, commit 后才返回 `Storage.Commit`.
调用方不能通过 `mode` 选项把写事务改成 deferred. SQL 不包含外部调用或网络等待.

- `{:ok, %Commit{facts: %Facts{intent: intent, revision: revision}, reply: reply, events: events}}`: 已提交决定.
- `{:error, reason_atom}`: 明确领域拒绝; 不产生待提交变化.
- `{:error, %Storage.Error{kind: :busy_exhausted | :unavailable | :indeterminate, cause: diagnostic}}`: 存储故障, 不能转为 Failed.

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

`history/6` 按 `read/3` 的 revision 固定审计范围, cursor 为 `{revision, position}`,
默认每页 100 条, 上限 1,000 条; `next: nil` 表示范围读取完毕. 晚到报告不会改变旧范围内的审计材料.
`discover/4` 返回 Prepared/Waiting/Unknown 或已到期 StartAuthorized 的候选, 默认上限 100, 最大 1,000.
候选不授予许可; 调用方须定期从头重扫, 并通过领域命令重验条件.

有限幂等需要可信 `contract_clock: fn -> resource_protocol_time end`, 在锁取得后采样.
该函数只能读取已核验的有界本地契约时钟, 不得访问网络或直接采用客户端时间.
未提供时按没有可重验的有限保证处理. 本实现不声称 SQLite 墙钟等于资源时间;
外部协议仍须保证延迟到达的过期 key 不重新产生效果.

## 验证边界

运行 `mix test --warnings-as-errors` 或在根目录运行完整 umbrella 测试.
SQL 测试使用真实临时文件, 覆盖独立 Repo 并发提交, 领取竞争, 原 grant/报告重投,
快照/报告/Outcome/History 原子回滚, 取消与完成竞争, 锁等待跨 expiry, busy 重试耗尽,
History 分页一致性, 回调完成和停止/重启 Repo 后的恢复. codec 另检查标签混淆和 64-bit 精确往返.

Repo 停止/重启与丢弃已提交回复不等于真实掉电或 commit 网络断连测试.
文件系统/磁盘掉电保证, 更细故障分类, PostgreSQL 符合性, Runtime 权限/验签/Worker 与真实 provider 条件仍需后续验收.
模型与代码对应关系见 [对照记录](../../model/implementation-conformance.md).
