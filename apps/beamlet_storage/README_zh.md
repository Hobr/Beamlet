# Storage 基础设施（数据集 format3）

[English](README.md)

`beamlet_storage` 提供显式 Ecto 资源、数据集安装与校验、事务、规范 JSON、共享二进制制品和引用校验。它没有 Application 回调；加载或启动依赖不会启动 Repo，也不会安装领域表。直接依赖 Ecto 3.14.0、Ecto SQL 3.14.0、ecto_sqlite3 0.25.0、Postgrex 0.22.4、Jason 1.4.5，并启用 OTP `:crypto`，不依赖其他 Beamlet 应用。

Actions 的 Operation、执行证据、结果、dispatch scopes 和 journal 属于 `beamlet_actions_storage`；Agent 的控制、事件、检查点、命令及继承属于 `beamlet_agent_storage`。产品组合与显式运维命令 `mix beamlet.storage.migrate` 属于 Node。基础库不根据 Repo 名或领域 kind 推断 profile、迁移或大小策略。数据集 format3 与 Agent 导出 trace format2 是不同协议。

## 开发与显式安装

从仓库根目录进入 `nix develop`（仓库工具链为 OTP 29 / Elixir 1.20），执行 `mix deps.get`、`mix compile`；以下示例在根目录 `iex -S mix` 中按需执行。SQLite 父目录必须存在，两个路径必须为本地绝对路径、无符号链接且不能互为硬链接或路径别名。`peer_database` 是显式隔离校验参数，不会因此创建第二个数据库。PostgreSQL 则需预先置备空数据库，显式提供 `database`、用户名及 socket/hostname 等连接选项，不使用 `url:`。

只安装共享基础表的示例（使用全新路径；会写入本地数据库）：

```elixir
alias Beamlet.Storage.{Dataset, Installation, SQLiteRepo}

# 也可由宿主定义自己的可信 Repo 模块：
# use Beamlet.Storage.Repo, adapter: :sqlite  # 或 :postgres

descriptor = %{
  profile: "foundation-example",
  format_version: 3,
  components: [Installation.foundation_component()],
  migrations: [Installation.foundation_migration()]
}

:ok = Installation.validate(descriptor)
dir = Path.join(System.tmp_dir!(), "beamlet-example-" <> Ecto.UUID.generate())
File.mkdir_p!(dir)
opts = [
  descriptor: descriptor,
  dataset_id: Ecto.UUID.generate(),
  database: Path.join(dir, "data.db"),
  peer_database: Path.join(dir, "peer.db")
]
{:ok, _pid} = Dataset.initialize(SQLiteRepo, opts)
:ok = Dataset.verify(SQLiteRepo, opts)
SQLiteRepo.stop()
{:ok, _pid} = Dataset.open(SQLiteRepo, opts)
# 后续示例使用这个已打开 Repo；结束时调用 SQLiteRepo.stop()。
```

保留真实环境中的 `dataset_id` 与 descriptor，重新打开时必须完全匹配。`initialize/2` 只处理全新目标，不覆盖已有数据；失败安装可能留下文件和不完整元数据，不自动清理或重试。`open/2` 不创建缺失 SQLite 文件、不升级、不修复；SQLite 在可写启动之前先只读预检。`verify/2` 对已运行 Repo 做只读验证，不负责打开或写入准入。初始化与打开成功返回链接 PID，由调用方关闭；若 Repo 模块已注册则返回 `:conflict`，不会停止他人拥有的实例。

描述符必须显式列出全部有序组件及迁移。foundation/version1 和迁移 ID1 必须在首位；迁移 ID 唯一且递增，每个组件都有迁移，模块唯一并为已编译的可信代码。基础安装只有 `artifacts`、单行 `storage_metadata` 和 Ecto `schema_migrations`。先记录 `installed=false`，完整列表成功后才标记完成。校验严格比较身份、format、profile、清单字符串、完成标记和迁移 ID；旧 authority2/journal1、额外/缺失组件或不完整安装均拒绝。清单保存模块身份而非源码哈希，发布后的迁移实现须保持不可变，不从磁盘选择代码，没有旧格式导入器或兼容门面。

## 事务、制品与引用

`Transaction.write/2` 拥有提交/回滚权，接受事务函数或 `Ecto.Multi`。`Transaction.participate/2` 要求同 Repo 已有事务，不创建嵌套提交；参与者的错误必须由外层显式回滚。普通函数返回 `{:error, reason}` 本身不会触发 Ecto 回滚。以下组合演示制品和引用共用一个提交边界：

```elixir
alias Beamlet.Storage.{Artifacts, Codec, References, Transaction}

bytes = <<0, 255>>
artifact_id = Ecto.UUID.generate()
attrs = %{
  id: artifact_id,
  digest: Codec.hash(bytes),
  media_type: "application/octet-stream",
  size: byte_size(bytes),
  content: bytes,
  recorded_at: DateTime.utc_now()
}

{:ok, :ok} = Transaction.write(SQLiteRepo, fn ->
  case Artifacts.put(SQLiteRepo, attrs) do
    {:ok, _artifact} -> :ok
    {:error, reason} -> SQLiteRepo.rollback(reason)
  end

  case References.verify(SQLiteRepo, %{"artifact_id" => artifact_id}) do
    :ok -> :ok
    {:error, reason} -> SQLiteRepo.rollback(reason)
  end
end)
{:ok, artifact} = Artifacts.fetch(SQLiteRepo, artifact_id)
true = artifact.content == bytes
:ok = References.verify_read(SQLiteRepo, %{"artifact_ids" => [artifact_id]})
```

制品最多 16MiB，必须带规范 UUID、准确 SHA-256、字节大小、媒体类型及时间。原始二进制不要求 JSON；读取重新校验内容和摘要。ID 和摘要各有唯一约束，重复插入返回 `:conflict`；按摘要寻找并复用已有记录是领域调用方的职责，不是 `put/2` 的隐式幂等行为。没有文件系统/对象存储副作用或 GC。

`References` 只识别字符串键 `artifact_id`、`artifact_ids`、`artifact_refs`；后两者必须为列表。`verify/2` 去重后交给事务内校验，最多 1024 个 ID；事务外返回 `:invalid_data`。`verify_read/2` 支持无写事务的重建。调用方须先限制 JSON 信封深度、大小和形状，引用遍历本身没有这些预算；只读路径也没有事务内列表的 1024 限制。缺失制品返回 `:artifact_missing`，无效身份或损坏内容返回 `:invalid_data`，不可用不会伪装成缺失。

## 规范 JSON

`Codec.encode/2`、`decode/2`、`digest/2` 接受正整数字节上限，默认 4MiB；领域库传入自己的预算，不能传领域 kind 原子。对象按字符串键排序，保留整数与浮点拼写差异，摘要为规范字节的小写 SHA-256；`Codec.hash/1` 则只散列原始 iodata，不校验 JSON。

```elixir
{:ok, ~s({"a":1,"z":2})} = Codec.encode(%{"z" => 2, "a" => 1}, 1024)
{:ok, %{"a" => 1}} = Codec.decode(~s({"a":1}), 1024)
{:error, :invalid_data} = Codec.decode(~s({"a":1,"a":2}), 1024)
{:ok, _digest} = Codec.digest(%{"a" => 1}, 1024)
```

编码和解码都执行 UTF-8、深度 32、节点 100000 和字节预算校验，拒绝重复对象键、结构体、非字符串键、运行时进程/引用等值。结构化凭据键递归拒绝，但 `secret_ref` 等引用键可保存，普通文本不是秘密扫描对象；内容政策仍由调用方负责。超出预算返回 `:limit`，内容不合法返回 `:invalid_data`。隐藏的 Ecto 参数化类型 `Beamlet.Storage.JSON` 要求 schema 显式设置 `max_bytes:`，损坏字节拒绝加载；基础 `Transaction.read/1` 仅对精确匹配的本类型 Ecto struct-load 错误返回安全 `:invalid_data`，其他编程异常继续抛出。

## 宿主所有权与准入

```elixir
alias Beamlet.Storage.{Admission, Host}
SQLiteRepo.stop()
{:ok, host} = Host.start_link(datasets: [%{key: :shared, repo: SQLiteRepo, options: opts}])
{:ok, %{shared: SQLiteRepo}} = Host.handles(host)
%{shared: :admitted} = Host.status(host)
{:ok, gate} = Admission.start_link([repo: SQLiteRepo] ++ opts)
:ok = Admission.consult()
:ok = Admission.failure(:storage_outcome_unknown)
{:error, :durable_not_admitted} = Admission.consult()
:admitted = Admission.status()
GenServer.stop(gate)
GenServer.stop(host) # 关闭该宿主成功打开的 Repo
```

Host 要求 key/Repo 分别唯一；打开失败保留安全原因，既不自动重开，也不关闭未成功取得的 Repo。`handles/1` 是已打开句柄，不代表当前可写；`status/1` 每次检查格式并做回滚写探针。Admission 可另外提供 `resources: [{repo, opts}]` 以检查共同依赖，或通过初始 `reason:` 保留打开失败。它是嵌入方显式启动的门；不存在时 `status/1` 为 `:not_configured`、`consult/1` 放行，`admitted?/1` 为 false。

`failure/2` 同步记录失败后，`consult/1` 持续拒绝，直到新鲜 `status/1` 成功清除；初始配置的拒绝原因不会通过探针自动消除。探针对元数据执行 UPDATE 后回滚，不提交，因此不验证提交或 fsync。进程/Repo 注册、Node ready 和探针结果都不保证下一次写入成功。

SQLite 连接使用 pool1、WAL/FULL/FK，普通事务 deferred、基础写事务 immediate；Exqlite 的 2000ms 可中断 busy handler 对应 `PRAGMA busy_timeout=0`，不能随意替换。PostgreSQL pool4，每条连接（包括重连）要求 `fsync` 和 `synchronous_commit` 为 on。

| 情况 | 结果与处理边界 |
| --- | --- |
| 描述符/UUID/选项无效 | `:invalid_data`，安装前拒绝 |
| SQLite 同路径或硬链接别名 | `:path_alias`；符号链接路径为 `:invalid_data` |
| 缺失目标 / 已有目标 | `:dataset_missing` / `:dataset_exists`，不创建或覆盖 |
| Repo 已注册 / 身份或 profile 不符 | `:conflict` / `:dataset_mismatch` |
| 不完整或不支持的安装 / 恢复备份标记 | `:schema_unsupported` / `:restored_backup` |
| 事务外 participate | `:transaction_required` |
| 确定的唯一性 / 数据约束拒绝 | `:conflict` / `:invalid_data`，事务回滚 |
| 读取驱动失败 | `:storage_unavailable`，不是无记录 |
| 未分类写入/断连失败 | `:storage_outcome_unknown`，不能确认是否提交 |
| 准入门拒绝 | `:durable_not_admitted`；底层探针可能返回 `:write_failed` 或不可用 |

结果未知时按稳定身份核对已有事实，不自动重试写入或外部副作用。备份必须一致（SQLite `.backup`/`VACUUM INTO` 或 PostgreSQL 一致备份）；`restored_backup` 是运维设置的阻断标记，不自动检测备份回滚。

## 验证入口

以下命令均从仓库根目录运行；子目录入口可能受到 umbrella 依赖选项不一致的既有问题影响。环境及执行结果应分别记录，不能把排除的 PostgreSQL 测试算作通过。

```sh
mix format --check-formatted apps/beamlet_storage/lib/beamlet/storage/*.ex apps/beamlet_storage/lib/beamlet/storage/schema/*.ex
mix compile --warnings-as-errors
mix test apps/beamlet_storage/test --seed 631927
elixir scripts/quality/check-contracts-test.exs
elixir scripts/quality/check-contracts.exs
```

PostgreSQL 套件需要隔离服务和建库权限，显式提供 `BEAMLET_PG_SOCKET_DIR`、`BEAMLET_PG_PORT`、`BEAMLET_PG_USER` 后从根目录运行：

```sh
mix test apps/beamlet_storage/test/beamlet/storage/foundation_postgres_test.exs --include postgres_db --seed 631927
```

格式检查、warning-fatal 编译、契约检查、完整测试及静态门的集成结果由任务验证报告记录。更多运维组合见[部署说明](../../scripts/deployment/README.md)。
