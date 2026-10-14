# Beamlet-Agent：持久调用方组合

`Beamlet.Agent.Caller` 提供基于独立 Intent 的持久 await-all，以及单个 Success 驱动后续 Effect 的可恢复决定。
它不是完整 LLM Agent loop、通用 Workflow 或调用栈恢复。
依据 [多 Intent / Tool Call 契约](../../model/spec/multi-intent-and-tool-calls.md) §1–8，
对应 Quint 的 `openRound`、`multiResolve`、`readDependency`、`collectRound` 与单步 Continuation。

## 职责与持久边界

- 调用方独立 SQLite 保存 `{owner, round_key}`、不可变完整依赖清单、slot→Intent、已读 Outcome 与最终 aggregate。
- `open/3` **只提交清单**，不向 Authority 发送任何请求；保存失败则不能开始发送。
- 每个依赖携带显式 slot、非空稳定 Submission Key 和完整 Definition；不从输入 hash、进程或重启次数生成身份。
- 一个 round 只路由到配置的一个 collection。owner 区分调用方清单，**不自动加入**引擎 Submission Identity。
- 相同 owner/key 和相同清单复用；改变 slot、身份或定义拒绝。清单按 slot 排序，传入列表顺序不改变含义。
- 不同 slot 可有意复用同一 Identity/Definition；同 Identity 异 Definition 提前拒绝。
- `advance/2` 提交原身份，保存对应 Intent ID，再通过 ReadFacts 读取结果。
  保存完整 Outcome，而不把报告、通知、外部 receipt 或完成数量当作结果。
- 全部 slot 都有结果时，在调用方事务内保存完整 aggregate。Failed/Cancelled 也是该 slot 的结果；
  Unknown/Pending/冲突阻塞仍未完成，不自动取消兄弟。
- 调用方进度写入使用短 immediate 事务；Authority 调用在事务外。**没有跨数据库原子提交。**
- 调用方的关联和已核验 Outcome 缓存也持久保存，属于额外工程材料，不直接照搬模型的易失 `agentLocals`。
  复用依赖 Authority Outcome 的不可变性及原数据库历史连续性。

使用**与 Authority、审批资源不同的数据库文件**。存储为 WAL/FULL；
数据库丢失、克隆或旧备份回滚不在恢复保证内，不能用同名新库代替原历史。

## Interface

| 操作 | 行为 |
| --- | --- |
| `start_link(database: path, ...)` / `migrate(repo)` | 显式启动、初始化真实调用方数据库；不自动启动生产 Agent |
| `new(repo, coordinator, owner)` | 配置可信本地 Coordinator 与调用方作用域 |
| `Dependency.new(slot, identity, definition)` | 验证稳定依赖，拒绝 unkeyed 和非法受限值 |
| `open(caller, key, dependencies)` | 原子 create-or-get 完整清单，不发送 Effect |
| `discover(caller, cursor \\ "", limit \\ 100)` | 分页列出已保存的 round key，重启不依赖内存中的清单；候选不代表完成 |
| `read(caller, key)` | 读取已提交调用方进度，不执行 Effect |
| `advance(caller, key)` | 一次有界恢复/收集；执行由 Runtime Worker/Scheduler 推进 |

`Round.intents`、`Round.outcomes` 按 slot 索引；
`Round.aggregate` 为 nil 表示尚未持久收齐，为 map 时每项包含 `"intent_id"` 和完整 `"outcome"`。
已完成 aggregate 可在 Authority 暂时离线时直接复用；这不撤回外部调用，也不重新启动已完成 Intent。

上层应定期调用 advance 或在通知后唤醒它；此模块不隐式启动轮询进程或超时终结。
owner、namespace、round key、Intent ID 都不是凭据。这里只接受受信本地应用能力，没有 HTTP/登录/远端 ACL。

## 本地 Echo 示例

在 umbrella 的 `mix run` / `iex -S mix` 中：

```elixir
alias Beamlet.{Definition, Identity}
alias Beamlet.Agent.Caller
alias Beamlet.Agent.Caller.Dependency
alias BeamletRuntime.{Coordinator, Scheduler, Worker}
alias BeamletRuntime.Handlers.Echo
alias BeamletRuntime.Storage.SQLite

{:ok, authority} = SQLite.start_link(database: "/tmp/beamlet-example-authority.db")
:ok = SQLite.migrate(authority)
coordinator = Coordinator.new(repo: authority, collection: "local",
  actor: "local-application", handlers: [{Echo, nil}])

{:ok, repo} = Caller.start_link(database: "/tmp/beamlet-example-caller.db")
:ok = Caller.migrate(repo)
caller = Caller.new(repo, coordinator, "agent-1")

{:ok, identity} = Identity.new("local", "agent-1", "echo-1")
{:ok, definition} = Definition.new(%{operation: "beamlet.echo.v1", input: "hello"})
{:ok, dependency} = Dependency.new("answer", identity, definition)

{:ok, _saved_manifest} = Caller.open(caller, "round-1", [dependency])
{:ok, _submitted} = Caller.advance(caller, "round-1")

{:ok, worker} = Worker.start_link(coordinator: coordinator, id: "worker-1",
  environment: %{"echo" => true})
{:ok, _page} = Scheduler.scan_once(coordinator, [worker])

# Task/报告提交是异步的；未收齐时保留 nil，稍后用相同 round key 再 advance。
{:ok, progress} = Caller.advance(caller, "round-1")
progress.aggregate
```

重启后复用原文件、owner、collection 和稳定 key；可先 discover 再 read/advance，
不重新生成依赖身份或 Definition。已接受 Intent 即使当前 Handler 暂缺也可重新定位；
新身份仍需当前合法 Handler/schema。

## 错误、故障窗口与限制

- 领域/清单错误返回 `{:error, reason}`，不会覆盖原 round。
- 外部提交/读取或进度持久化失败可返回 `{:error, %Caller.Error{stage: ..., slot: ..., reason: ...}}`。
  该次 advance 遇错停止，之前的进度保留；重试原身份。错误**不是 Failed Outcome**。
- 本地 SQL 故障可能返回 `:caller_commit_indeterminate`，不能断言未提交；
  用原 owner/key read/open/advance 恢复。没有忙锁自动重试/公平性承诺。
- 保存清单后退出：从原清单继续。Authority 接受后回复/调用方写入丢失：
  重投原 Identity/Definition，找回原 Intent，而非创建语义相同的新操作。
- Authority 已 Closed、调用方尚未保存结果：ReadFacts 取回原 Outcome，不再创建 Execution。
- 不支持空清单、unkeyed、多个 collection 同轮、await-any/quorum、自动取消或自动运行任意决策循环。
- 每轮 1–256 个 slot，分页最多 1,000；编码后 manifest/progress 各最多 16 MiB。
  后续结果导致容量不足也只返回存储错误，不改写引擎事实或伪造终态。
- 保存 aggregate/decision 不保证后续 LLM/业务代码或外部副作用只执行一次；后续 Effect 须继续使用原持久身份。

## 单步持久决定与 Continuation

原 round 有 A/B；通过 `advance` 收集 A 的 Succeeded 后，可保存一个决定并驱动 C，
无需等待 B。Pending/Unknown/Failed/Cancelled 不能成为本单步规则的消费结果。
decision 不让原 round 提前完成，也不改变 B 的生命周期或 Outcome。

| 操作 | 行为 |
| --- | --- |
| `decide(caller, computation, step_key, opts, planner)` | 原子 create-or-get 单步决定；首次调用验证来源并计算候选，已有记录直接复用 |
| `read_decision/3` | 读取原消费材料、规则版本、选择值与后续 Definition/Identity，不运行 planner |
| `discover_decisions(caller, computation, cursor \\ "", limit \\ 100)` | 查找已有步骤，包括决定已存但后续清单尚未建立的窗口 |
| `register_next/3` | 只根据已提交决定建立后续清单，不发送 C |
| `advance_next/3` | 幂等恢复后续清单，随后以原身份 submit/read/汇总 |

稳定身份为 `{owner, computation, step_key}`。决定保存原 round、slot、Intent、完整 Outcome、
规则版本、受限值选择内容、后续 round 和一个完整 Dependency。
后续输入必须严格等于消费的 Outcome.value，后续提交身份必须不同于原清单中的身份，
对齐 `continuation/logic.qnt` 的单步输入传递。此处不提供任意变换输入、多消费集合或自动 LLM loop。

`opts` 是且仅是 `source_round`、`source_slot`、`rule`；rule 是可信应用指定的语义版本，
不是动态模块名，也不提供治理规则登记/ACL。
`planner` 接收完整 Outcome，只计算并返回
`{:ok, %{value: restricted_value, next_round: stable_key, dependency: dependency}}`。
它在 SQL 事务外运行，不能承担发送 Effect 的职责；异常/exit/非法回复不产生决定。
调用方收集的 Outcome 是此前 ReadFacts 已核验的不可变结果，新的决定在 SQL 保护内重新核对原 slot/结果关联。

**冲突策略：先提交者生效。** 相同决定身份已有记录时，不运行 planner、不应用新 opts，
直接返回原记录；并发候选可能都计算，但后提交者使用原决定。不能依赖 planner 只执行一次。
需要另一个逻辑决定必须使用新 step_key；新通知或 B 完成不能改变原决定。

提交顺序：

1. 调用方已保存原清单并收集合格 Success。
2. `decide` 只提交不可变决定；此时后续 round 仍不存在。
3. `register_next` 从原记录建立清单。
4. `advance_next` 或该 round 的 `advance` 提交 C；回复丢失仍复用原身份。

决定原子保留后续 round 名称，同 owner 下只能由一份决定保留；
`open` 也验证该 round 的完整清单，不能换 key/输入。
如果 round 在决定之前已存在，首次决定返回 `:successor_round_exists`，即使清单相同也不追认。
重启应先 `discover_decisions` / `read_decision` 再 `advance_next`，不重新生成决定或 C 身份。

在上面的 Echo 示例中收集到 answer 后：

```elixir
{:ok, decision} = Caller.decide(caller, "computation-1", "step-1",
  [source_round: "round-1", source_slot: "answer", rule: "copy-success.v1"],
  fn outcome ->
    {:ok, next_identity} = Identity.new("local", "agent-1", "echo-2")
    {:ok, next_definition} = Definition.new(%{operation: "beamlet.echo.v1", input: outcome.value})
    {:ok, next_dependency} = Dependency.new("follow-up", next_identity, next_definition)
    {:ok, %{value: %{"choice" => "echo"}, next_round: "round-2", dependency: next_dependency}}
  end)

{:ok, _manifest} = Caller.register_next(caller, "computation-1", "step-1")
{:ok, _progress} = Caller.advance_next(caller, "computation-1", "step-1")
{:ok, _page} = Scheduler.scan_once(coordinator, [worker])
decision.outcome
```

只读/不可用数据库导致决定或清单不能提交时，禁止该路径继续发送。
`:caller_commit_indeterminate` 仍须按原身份 read/重试；决定尚未提交时可重新计算，
一旦成功提交就必须复用原选择。C 已 Closed 后读取原 Outcome，不创建新 Execution。

`migrate` 增加 schema v2 决定表，保留 v1 清单/进度编码；有真实 v1 数据升级测试。
新程序使用前必须完成迁移。不承诺 v1/v2 程序混合写入：旧程序没有保留清单检查，
也不提供备份回滚或克隆隔离保证。

## 验收

`cd apps/beamlet_agent && mix test --warnings-as-errors`。
19 个 Caller 集成测试使用真实独立的调用方、Authority 和审批 SQLite 数据库，覆盖：
清单先于发送、不可变重投、同/异调用方身份、同 Intent 多 slot、三依赖部分恢复、
Unknown、Failed/Cancelled 兄弟隔离、独立 Repo 并发、接受回复丢失、真实只读写故障、
Authority 离线/调用方重启、Handler 暂缺、未知格式、容量限制及分页发现。

另有 20 个 Continuation 集成测试覆盖原部分结果推进、决定/清单保存后的重启、调用方进程强杀、C 接受回复丢失、C 离线完成、B
迟到、独立 Repo 竞争、实际只读故障、作用域及 v1 数据升级。 有限工程测试不等于 SQL/调用方到 Quint 的无界 refinement
证明。
