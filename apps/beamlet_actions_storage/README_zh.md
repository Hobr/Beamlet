# Actions Storage

`beamlet_actions_storage` 为通用 Operation 保存执行事实，供 Runtime 和事务组合调用方使用。加载应用不会启动 Repo，也没有 Application 回调。实际 umbrella 依赖为 `beamlet_actions`、通用 `beamlet_storage`，另直接声明 Ecto/SQL、SQLite/Postgrex、Jason；不依赖 Agent、Core 或宿主。

## 事实与事务边界

Authority 拥有 `operations`、`executions`、`execution_evidence`、`operation_events`、`dispatch_scopes`；执行端本地 SQLite journal 拥有 `journal_attempts`。foundation 提供数据集、规范 JSON、事务和 artifact；Agent 的所有者、turn、step、role、ordinal、generation 和有序来源属于 [Agent Storage](../beamlet_agent_storage/README_zh.md) 的关联。

`OperationRecords.prepare/2` 提交不可变描述、一个 prepared attempt 及 `operation.prepared` 事件，成功后才允许派发。`claim_dispatch/2` 单次将 prepared 改为 send_claimed；`record_evidence/2` 保存观察证据，`accept_result/2` 用 Operation 版本 CAS 接受唯一 Result 并追加独立的接受事件。接受不推进 Agent 序列，不等于 Agent 已消费输出。中立存储的 Result 是有界 JSON；完整执行协议由 Actions/Runtime 调用方验证。

prepare 的相同逻辑身份可重放，描述或执行端/boot 改变冲突；证据按 executor_id/evidence_id 去重。相同已接受 Result 与证据可重放，不同结果拒绝。派发认领只能成功一次。`prepare_in_transaction/2` 和 DispatchScopes 的事务参与者要求同一个 Repo 已有事务，不独立提交，调用方必须将任何错误传播为整组回滚。锁顺序为 scope → Operation；Agent 组合再在前面锁 Agent。scope epoch 轮换阻止旧代新认领，不证明已有外部工作停止。重授权仅供显式继续，不能重授权 claimed 未决 attempt。

`ExecutorJournal.claim_start/2` 按 authority/attempt 登记一次意图，重复返回已有状态，调用方不能再次启动 worker。首个 deadline/cancelled 原因保留；终态、附件及回执原子写入，日志事务规范编码总预算 32 MiB。重启遗留意图标为 `unknown_after_restart`，不会推断未执行或重新启动。`TerminalArtifacts` version1 最多 64 项，单项及解码总量各 16 MiB，编码 24 MiB；校验 base64/摘要/大小，只证明内容完整性，authority artifact 存在性仍需在 authority 中验证。

## 数据集与调用示例

从仓库根目录进入 `nix develop`，工具链为 OTP 29 / Elixir 1.20；必要时运行 `mix deps.get`、`mix compile`。这是显式调用库，需先选择 Repo 与完整的可信安装描述符：

- `Profiles.authority/0`：`actions-authority`，容器 format3，组件 foundation1 / actions-authority1，迁移 1 / 100。
- `Profiles.journal/0`：`actions-journal`，容器 format3，组件 foundation1 / actions-journal1，迁移 1 / 200。

format3 是数据集容器格式，与 Agent trace format2 无关。`Dataset.initialize/2` 仅安装全新目标；`Dataset.open/2` 仅打开完全匹配的现有数据集，不迁移、转换或修复旧格式。SQLite 需要已存在父目录、绝对且互不别名的 database/peer_database 路径；PostgreSQL authority 需预先置备空数据库及显式连接选项。成功返回链接 Repo PID，由调用方关闭。`dataset_id` 必须保存并在重新打开时原样使用，不能每次生成新身份。

以下在根目录 `iex -S mix` 中使用全新临时 SQLite 路径，不执行 Handler 或外部工作：

```elixir
alias Beamlet.Actions.Storage.{SQLiteAuthorityRepo, Profiles, OperationRecords}
alias Beamlet.Storage.Dataset

repo = SQLiteAuthorityRepo
dir = Path.join(System.tmp_dir!(), "actions-example-#{Ecto.UUID.generate()}")
File.mkdir_p!(dir)
opts = [database: Path.join(dir, "authority.db"),
        peer_database: Path.join(dir, "journal.db"),
        dataset_id: Ecto.UUID.generate(), descriptor: Profiles.authority()]
{:ok, _pid} = Dataset.initialize(repo, opts)
attrs = %{
  operation: %{id: Ecto.UUID.generate(), description: %{
    "kind" => "example.echo", "protocol_version" => 1,
    "payload" => %{"text" => "hello"}}},
  attempt: %{attempt_id: Ecto.UUID.generate(), executor_id: Ecto.UUID.generate(),
             executor_boot_id: Ecto.UUID.generate(), budget: %{}}
}
{:ok, prepared} = OperationRecords.prepare(repo, attrs)
{:ok, ^prepared} = OperationRecords.prepare(repo, attrs)
{:ok, stored} = OperationRecords.fetch(repo, prepared["operation_id"])
"prepared" = stored["attempt"]["dispatch_state"]
repo.stop()
{:ok, _pid} = Dataset.open(repo, opts)
repo.stop()
```

要安装 journal，使用 `ExecutorJournalRepo`、`Profiles.journal/0` 及独立 database/dataset_id，并将 peer_database 指向 authority 路径。产品角色配置与资源监督属于 Node，不能根据 Repo 名称推断安装 profile。

## 错误与验证

属性门面采用原子键 map，返回普通字符串键数据。`invalid_data` / `limit` 拒绝非法和超限 JSON；`conflict` 表示身份、版本或唯一性不符；`stale_epoch` 表示派发授权过期。读失败返回 `storage_unavailable`，无法确定的写入返回 `storage_outcome_unknown`，必须以稳定身份读取核对，不自动重试业务。严格 JSON 损坏在读和写门面均安全归类，其他程序异常保留原始异常。规范编码拒绝结构化凭据字段，但字符串不是秘密扫描器；调用方仍须排除凭据。

从仓库根运行：

```sh
mix format --check-formatted apps/beamlet_actions_storage/lib/beamlet/actions/storage/*.ex apps/beamlet_actions_storage/lib/beamlet/actions/storage/{schema,migrations}/*.ex
mix test apps/beamlet_actions_storage/test
```

SQLite 契约及 journal 测试默认运行；PostgreSQL 测试需要私有、可丢弃集群及 `BEAMLET_PG_SOCKET_DIR`，可选 `BEAMLET_PG_PORT` / `BEAMLET_PG_USER`，缺少时被排除。不能把排除算作适配器通过。集成检查在根运行 `mix compile --warnings-as-errors` 和 `elixir scripts/quality/check-contracts.exs`。这套协议不承诺外部副作用 exactly-once、物理跨机或断电恢复验收。
