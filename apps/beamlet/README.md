# Beamlet 领域核心

本应用实现 Effect Engine 的纯领域规则, 不依赖 Runtime, Agent, Ecto, 网络或系统时钟.
`beamlet_runtime` 依赖本应用, 后续负责事务存储与执行编排.

## 当前实现

- `Beamlet.Value`: 受限逻辑值 v1, 确定规范表示, 精确相等与字节/节点/容器深度预算.
- `Beamlet.Definition` / `Identity`: 不可变操作定义, 初始策略默认值, 稳定提交身份及冲突检查.
- `Beamlet.Domain`: 第一轮执行的建立, 领取, 续租, 到期, 启动授权, Worker 报告及取消.
- `Intent` / `Execution` / `Outcome` / `Report`: 当前领域快照与不可覆盖证据.
- `Beamlet.Transition`: 新快照, History 增量和处理结果, 供 Storage 同事务保存.

已授权后到期保留 grant 并进入 Unknown; Waiting 不因 lease 到期退回 Unknown.
同 token 的授权重投返回原 Handler/资源/完成关联, 即使 lease 已到期或 Intent 已 Closed.
相同报告重投不重复审计; 矛盾报告保留全部内容及冲突, 不覆盖已有 Outcome.
`StopOnFailure` 的合格失败与终结增量一起返回. 取消只终结 Intent, 不表示外部停止.

当前是 [实现路线](../../model/spec/implementation-roadmap.md) 阶段 1 的首批交付.
安全替代和完整 RetryOnce 决策, callback/query 来源, Operation 专用 schema 校验,
真实 Storage/Handler/Worker 与 Transport 尚未实现.
`RetryOnce` 的失败暂时保留为 Open/Resolved, 不自动制造新尝试或 Failed.
Pending 当前只处理带原 Worker token 的证据, 须已保存 completion binding;
完整的独立第三方完成入口将在 Runtime/Adapter 接入时实现.

## Interface

`Domain.new_intent/4` 接收 Storage 分配的 Intent ID, 已验证的 Identity/Definition,
以及显式 `%{now: authority_epoch_ms, actor: trusted_actor}`.
幂等上下文包含 collection 和 Intent ID, 后续 Handler 必须保持其外部 key 映射稳定.
`Domain.resubmit/3` 只比较 Storage 已定位的同一 keyed 身份与原定义; 不负责全库去重或分配新身份.

`Domain.transition/3` 接收已提交一致快照, 命令和同样的可信上下文:

| 命令 | 作用 |
| --- | --- |
| `{:create_execution, execution_id}` | 建立唯一当前 Prepared; 已存在身份返回原事实 |
| `{:claim, execution_id, worker, incarnation, expected_generation, ttl_ms}` | 分配 generation, 或重取仍有效的原领取; Prepared 才可重新分配 |
| `{:renew, token, ttl_ms}` | 验证当前完整 token, 延长 lease, 不缩短或记录普通心跳 |
| `{:expire, execution_id}` | 到期时产生持久失效屏障和必要 Unknown |
| `{:authorize, token, binding}` | 验证启动条件, 保存唯一 grant 和原 binding |
| `{:record_report, report}` | 保存/去重 Worker 证据, 判断冲突和合格终结 |
| `{:cancel, reason}` | 保存逻辑取消; 已 Closed 返回原 Outcome |

所有 ID 在当前 Interface 中为非空 UTF-8 字符串, 上限 256 bytes. Lease generation 为非回绕正 64-bit 计数,
时间使用有符号 64-bit epoch 毫秒, 相等即到期. 身份不自动归一化, 也不充当凭据.

返回 `{:ok, %Transition{intent: snapshot, events: history_delta, reply: result}}` 或 `{:error, reason}`.
前者是待提交决定, 不代表 Durable Stored. 到期拒绝可以在 Transition 中携带
`reply: {:rejected, :lease_expired}` 和失效事件, Storage 须提交屏障后再回复拒绝.
普通错误不返回待保存变化. History 的物理身份/提交组次序由 Storage 在原子保护内分配.

Runtime 必须先核验 principal/操作权限, Worker 来源, Handler 登记, 资源/硬约束及 Operation 的输入/结果 schema.
binding 是可信配置/Adapter 提供的受限值快照, 至少含 operation, handler, protocol, resource;
支持 Pending 时另含可恢复 completion 材料. 不能把外部正文直接当作可信 binding 或 Report.

## 可运行的领域路径

在仓库根目录运行 `iex -S mix`, 然后执行:

```elixir
alias Beamlet.{Definition, Domain, Identity, Report}

context = %{now: 1_000, actor: "local-authority"}
{:ok, definition} = Definition.new(%{operation: "api.request.v1", input: %{"prompt" => "hello"}})
{:ok, identity} = Identity.new("local", "agent-1", "turn-1/call-1")
{:ok, created} = Domain.new_intent("intent-1", identity, definition, context)
{:ok, prepared} = Domain.transition(created.intent, {:create_execution, "execution-1"}, context)
{:ok, claimed} = Domain.transition(prepared.intent,
  {:claim, "execution-1", "worker-1", "session-1", 0, 5_000}, context)
{:claimed, token} = claimed.reply

binding = %{
  "operation" => "api.request.v1",
  "handler" => "example-handler.v1",
  "protocol" => "example-protocol.v1",
  "resource" => %{"account" => "account-1"}
}
{:ok, authorized} = Domain.transition(claimed.intent, {:authorize, token, binding}, context)

# 这里仅提供示例证据. 实际 Worker 必须先取得已提交授权, 再在事务外调用 Handler.
report = %Report{id: "response-1", token: token, operation: "api.request.v1",
  kind: :success, body: %{"answer" => "hello"}}
{:ok, completed} = Domain.transition(authorized.intent, {:record_report, report}, context)
completed.intent.outcome
# %Beamlet.Outcome{kind: :succeeded, value: %{"answer" => "hello"}, ...}
```

## 验证与规格对应

从仓库根目录运行 `mix test apps/beamlet/test`.

| 规格 | 代码测试覆盖 |
| --- | --- |
| [持久值与消息](../../model/spec/persistent-values-and-messages.md) §1–3 | 数值/Unicode/规范字节, 预算边界, 定义相等, keyed 重投与冲突 |
| [存储命令](../../model/spec/storage-command-contracts.md) §2–4 | 领取响应丢失/重投, 竞争顺序, 原 grant, 到期拒绝增量, 计数/时间溢出 |
| [核心状态机](../../model/spec/core-state-machines.md) §2–6 | Open/Closed, Unknown, Pending, Resolved, 冲突与迟到证据, 成功/失败/取消 |
| [lease 与权限](../../model/spec/leases-and-permissions.md) §3–5 | incarnation/generation/token 作用域, expiry 相等, 回拨不复活, lease 与结果资格分离 |

这些是纯规则的行为测试. 竞争顺序测试不替代真实 SQL 并发、回滚、重启或持久性测试.
值规范表示接受已解码数据; wire decoder 还必须拒绝重复 JSON key, float/指数词法等无损解释问题.
Quint 源码和 SPEC 保持原语义, 本批实现没有修改模型来迁就代码.
