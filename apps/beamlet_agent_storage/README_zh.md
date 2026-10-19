# Agent Storage

[English](README.md)

`beamlet_agent_storage` 拥有 Agent 原始输入、控制事件、命令响应、可选检查点、不可变 Operation 关联及继承引用。它是无 Application 回调的显式存储库，加载不会启动 Repo。实际依赖为 `beamlet_actions_storage`、foundation `beamlet_storage`，并直接声明 Ecto/SQL、SQLite/Postgrex、Jason；不依赖 Agent、Core、Runtime、Node 或宿主。模型调用、进程生命周期、策略 reducer 及离线 trace 验证由上层 Agent 承担。

## 所有权与写入流程

本层拥有 `agents`、`agent_events`、`commands`、`checkpoints`、`agent_operations`，以及只读 SQL 视图 `agent_operation_projections`。关联保存 owner/turn/step/role/ordinal/tool-call、owner_generation、prepared_seq 和有序 sources；[Actions Storage](../beamlet_actions_storage/README_zh.md) 拥有中立描述、attempt、证据、accepted Result 与独立 `operation_events`。`Schema.Operation` 联接两层事实供读取，不能作为中立 Operation 写入口。`OperationRecords.fetch/2` 返回字符串键 operation/attempt；`History.operation_event/3` 仅为 trace 将 Actions 事件投影为 scope_id，不混入 Agent 日志。

`AgentRecords` 的写命令采用原子键属性，带稳定 `command_id` 及适用的 `position`（agent_id、lock_version、generation），返回字符串键响应。相同 command_id 和完整请求摘要返回原始响应，即使后来状态已推进；改变请求返回 conflict。generation 先于 lock_version 检查，阻止旧代写入。并发竞争可能冲突，不能据此自动重试业务。

`accept_input/2` 在请求准备前提交唯一 `%{"text" => text}` 原始输入，最大 64 KiB。`prepare_operations/2` 接受 1..8 个 operation/attempt，校验当前 turn、所有者、来源、ordinal 和仅含引用的 orchestration；在同一个 Repo 外层事务中调用 Actions 的 prepare 参与者，并写关联、Agent 事件、命令响应。任一成员失败全部回滚。只有提交后才可交给 Runtime。Result 接受不改变 Agent 序列，`consume_results/2` 再以摘要、角色、turn 和当前代验证引用并记录消费；后续请求只能使用已消费的输出，不能使用未消费证据。完整事件策略仍由 Agent/Core 在提交前预检，存储校验不代替 reducer。

create/fork 创建独立、不透明 dispatch scope。restore 按 Agent → scope → Operation 的全局顺序进入事务，递增 generation、轮换 epoch，记录暂停的激活事实，不执行模型或工具。显式继续采用旧代 accepted 输出时只更新关联资格；旧代 prepared 工作须在同一事务经 Actions 重授权，claimed 未决工作拒绝。继续后必须重新读取 Operation lock_version/scope/epoch 作为 Runtime 提交绑定；旧命令重放仍返回原响应，不能将其当刷新后的许可。描述与有序来源保持固定。

## 安装与调用

从仓库根进入 `nix develop`（OTP 29 / Elixir 1.20），按需 `mix deps.get`、`mix compile`。`Profiles.authority/0` 提供可信 `agent-authority` 容器 format3 描述符：foundation1 / Actions authority1 / Agent1，迁移依次 1 / 100 / 300。format3 与 trace format2 分别版本化。`SQLiteAuthorityRepo` 和 `PostgresAuthorityRepo` 只选择适配器，不隐式选择或安装 profile。

`Dataset.initialize/2` 仅安装全新目标；`Dataset.open/2` 不创建、补装、修复或转换旧数据集。SQLite 要求已存在父目录、绝对且互不别名的 database 与 peer_database；PostgreSQL 需宿主预先创建空数据库并提供连接参数。保存规范 dataset UUID，打开时沿用；恢复备份标记和旧格式均明确拒绝。成功启动的链接 Repo 由调用方关闭。

以下可在根 `iex -S mix` 使用全新临时目录。仅演示存储命令，不启动 Agent 或执行请求：

```elixir
alias Beamlet.Agent.Storage.{SQLiteAuthorityRepo, Profiles, AgentRecords, History}
alias Beamlet.Storage.Dataset
repo = SQLiteAuthorityRepo
dir = Path.join(System.tmp_dir!(), "agent-example-#{Ecto.UUID.generate()}")
File.mkdir_p!(dir)
authority_id = Ecto.UUID.generate()
opts = [database: Path.join(dir, "authority.db"),
        peer_database: Path.join(dir, "journal.db"),
        dataset_id: authority_id, descriptor: Profiles.authority()]
{:ok, _pid} = Dataset.initialize(repo, opts)
create = %{id: Ecto.UUID.generate(), command_id: Ecto.UUID.generate(),
           authority_id: authority_id, definition: %{"version" => 1}}
{:ok, created} = AgentRecords.create_agent(repo, create)
position = %{agent_id: create.id, generation: created["generation"],
             lock_version: created["lock_version"]}
input = %{command_id: Ecto.UUID.generate(), position: position,
          turn_id: Ecto.UUID.generate(), input: %{"text" => "你好"}}
{:ok, accepted} = AgentRecords.accept_input(repo, input)
{:ok, ^accepted} = AgentRecords.accept_input(repo, input)
{:ok, page} = History.event_page(repo, create.id,
  after_seq: 0, through_seq: accepted["through_seq"], limit: 100)
["agent.created", "input.accepted"] = Enum.map(page["events"], & &1["type"])
repo.stop()
{:ok, _pid} = Dataset.open(repo, opts)
repo.stop()
```

`command_response/3` 可在未知写入结果后读取原始提交响应。`fetch/2` 只返回 Agent 行和 head_checkpoint=nil；缓存应单独通过 `History.checkpoint_at/3` 读取。

## 继承与只读投影

`Inheritance` 构建同 authority 的扁平不可变引用：最多 128 个有序来源、1024 个闭包成员，遍历期限 5 秒。输入正文作为规范 JSON artifact 按摘要去重，保留原事件/Agent 身份；继承 Result 保留原 Operation 的所有权、描述和接受摘要。分叉只写子 Agent 的 created/forked/context.inherited 三条初始事件，不修改源行，也不复制 pending、attempt、命令去重或 provider 会话。验证清单不递归回放父 Agent 历史，但仍必须保留所引用的 artifact、Operation、关联及准备/接受事实；当前无 GC，内容缺失或损坏会阻止重建。继承的使用量不是子 Agent 新执行或计费。

安全分叉位置、活动实例退役、默认 unconfirmed 环境风险及显式继续决策由上层 Agent 检查；存储 fork 不证明远程工作已停止，读取或导出不授予执行权限。检查点仅是带摘要的控制/引用缓存，不含 messages/assistant；缺失或损坏时 `checkpoint_at/3` 返回 nil，由 Loader 回放历史。

`History.event_page/3` 按 seq keyset 分页，默认 100 行、最大 500 行，正文字节预算默认/最大 4 MiB（最小 4096）。单条超预算事实完整返回并标记 over_budget，不拆分记录；满页的 next_cursor 可能需再读空页确认结束。调用方须固定并沿用 through_seq，不存在跨页读事务。turns 以首序列分页；operations 以不可变 prepared_seq 分页，接受不会移动游标，但 Result 内容仍可能更新。完整导出由 Agent 固定独立 Operation 高水位，不能以 Agent seq 代替接受时间。`History.evidence/2` 最多 32 条并探测第 33 条，溢出返回 limit；普通 operation 查询只带最多 32 条，不可当作完整导出保证。

## 验证与限制

根目录命令：

```sh
mix format --check-formatted apps/beamlet_agent_storage/lib/beamlet/agent/storage/*.ex apps/beamlet_agent_storage/lib/beamlet/agent/storage/{schema,migrations}/*.ex
mix test apps/beamlet_agent_storage/test
mix test apps/beamlet_agent/test/beamlet/fork_test.exs apps/beamlet_agent/test/beamlet/history_export_test.exs
```

契约测试为 SQLite 和 PostgreSQL 使用隔离数据集；完整 Agent Storage 套件要求可丢弃私有 PostgreSQL 集群及 `BEAMLET_PG_SOCKET_DIR`，可选 `BEAMLET_PG_PORT` / `BEAMLET_PG_USER`。其 PostgresContractTest 未标记为 postgres_db 排除项，未配置时会在 setup 失败；不能将缺少环境当作通过。上层 Agent 集成可另用 `BEAMLET_AGENT_TEST_ADAPTER=postgres`。根集成门禁包括 `mix compile --warnings-as-errors`、`elixir scripts/quality/check-contracts.exs`。

非法结构/超限分别返回 invalid_data/limit；旧 generation 返回 stale_generation，身份或版本不匹配返回 conflict，未决执行返回 unresolved_execution。读失败与缺失分开，未知写入结果返回 storage_outcome_unknown，须核对稳定命令响应，不能自动执行重试。严格 JSON 加载损坏在读写门面都安全归类，不吞掉其他程序错误。模型凭据保持瞬态，不承诺凭据恢复、安全擦除、外部副作用 exactly-once、物理跨机或断电验收。
