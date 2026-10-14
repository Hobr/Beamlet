# Beamlet 领域核心

本应用实现 Effect Engine 的纯领域规则, 不依赖 Runtime, Agent, Ecto, 网络或系统时钟.
`beamlet_runtime` 依赖本应用, 后续负责事务存储与执行编排.

## 当前实现

- `Beamlet.Value`: 受限逻辑值 v1, 确定规范表示, 精确相等与字节/节点/容器深度预算.
- `Beamlet.Definition` / `Identity`: 不可变操作定义, 初始策略默认值, 稳定提交身份及冲突检查.
- `Beamlet.Domain`: 执行的建立, 领取, 续租, 到期, 启动授权, 安全替代, 报告, 策略停止及取消.
- `Beamlet.Recovery` / `Binding`: 独立重试依据, 原资源/幂等协议核验与 RetryOnce 预算规则.
- `Beamlet.Report.Source` / `Exclusion`: 独立 callback/query 作用域与可信的既往及未来执行排除证据.
- `Intent` / `Execution` / `Outcome` / `Report`: 当前领域快照与不可覆盖证据.
- `Beamlet.Transition`: 新快照, History 增量和处理结果, 供 Storage 同事务保存.
- `Beamlet.Judgment` / `Reconciliation`: 当前证据判断、独立审查版本、冲突处置、采用/排除/撤销与持久命令结果.

已授权后到期保留 grant 并进入 Unknown; Waiting 不因 lease 到期退回 Unknown.
同 token 的授权重投返回原 Handler/资源/完成关联, 即使 lease 已到期或 Intent 已 Closed.
相同报告重投不重复审计; 矛盾报告保留全部内容及冲突, 不覆盖已有 Outcome.
`StopOnFailure` 的合格失败与终结增量一起返回. 取消只终结 Intent, 不表示外部停止.

当前实现 [实现路线](../../model/spec/implementation-roadmap.md) 阶段 1 的纯领域规则，并接入后置证据协调增量。
`RetryOnce` 最多建立两个尝试, 已建立但未调用也消耗预算. 合格 Failure 在不能安全重试或预算耗尽时终结;
存在旧 Unknown, 未解释旧 Success 或冲突时保持 Open. 没有安全依据不建立后续尝试.
Pending 的完成可来自原 Worker 或独立 callback/query; 完成可先于 Pending 到达.
[SQLite Storage](../beamlet_runtime/README.md) 已开始实现真实事务、快照/History 保存及重启恢复.
本地 Coordinator/Scheduler/Worker 与静态 Handler 登记已接入, 示例 Echo 提供 Operation schema 校验.
真实外部 Provider Adapter, 远端认证与 Transport 尚未实现; 见 [Runtime 说明](../beamlet_runtime/README.md).

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
| `{:record_report, report}` | 保存/去重 Worker, callback 或 query 证据, 判断冲突和合格终结 |
| `{:replace_execution, old_id, new_id, reason}` | 重验安全依据, 失效旧 lease, 建立新 Prepared/current, 保存原依据; 同身份/理由重投返回已建立尝试 |
| `{:stop_known_failure, execution_id}` | 策略停止时接受合格的已存当前错误; 已 Closed 返回原 Outcome |
| `{:cancel, reason}` | 保存逻辑取消; 已 Closed 返回原 Outcome |
| `{:reconcile, command, policy, access}` | 按原审查版本、可信 Policy/权限核验采用/排除/撤销，保存原命令或明确拒绝 |

所有 ID 在当前 Interface 中为非空 UTF-8 字符串, 上限 256 bytes. Lease generation 为非回绕正 64-bit 计数,
时间使用有符号 64-bit epoch 毫秒, 相等即到期. 身份不自动归一化, 也不充当凭据.

返回 `{:ok, %Transition{intent: snapshot, events: history_delta, reply: result}}` 或 `{:error, reason}`.
前者是待提交决定, 不代表 Durable Stored. 到期拒绝可以在 Transition 中携带
`reply: {:rejected, :lease_expired}` 和失效事件, Storage 须提交屏障后再回复拒绝.
普通错误不返回待保存变化；协调的明确领域拒绝返回待提交 Transition，以保留原命令身份与拒绝结果。
History 的物理身份/提交组次序由 Storage 在原子保护内分配。

协调保留原始 Knowledge/报告及历史冲突，通过 `Judgment` 解释当前证据。
`Recovery.basis/3` 必须同时接收 Intent，以免把已排除的原始 Knowledge 当作当前安全依据。
完整提案、可信核验、规则版本、部分取代/撤销及存储升级见 [协调说明](../beamlet_runtime/RECONCILIATION.md)。

Runtime 必须先核验 principal/操作权限, Worker 来源, Handler 登记, 资源/硬约束及 Operation 的输入/结果 schema.
binding 是可信配置/Adapter 提供的受限值快照, 至少含 operation, handler, protocol, resource;
支持 Pending 时另含可恢复 completion 材料, 支持查询时保存 query binding.
不能把外部正文直接当作可信 binding 或 Report.

## 恢复依据与报告来源

`ReplaceExecution` 根据保存事实导出依据。`repeat_accepted` 默认为 false；只能在原 Definition 中显式指定布尔值，
不能在重试时临时开启或改变原已接受定义：

| 依据 | 必要条件 |
| --- | --- |
| `:unstarted` | 原尝试从未取得启动授权 |
| `:not_executed` | 可信 query Adapter 已验证原尝试既往及未来执行均被外部协议排除 |
| `:idempotency` | 原外部 resource/scope/protocol/key 保持一致, 原保证与新尝试保证仍适用 |
| `:repeat_accepted` | 原不可变 Definition 明确接受重复效果风险；不表示旧执行已停止 |

有合格依据时，冲突不再一律阻止替代/后续授权/调用；终结仍须满足当前冲突、旧成功及未知风险守卫。
[资源 fencing 与风险策略](../beamlet_runtime/FENCING.md) 给出新本地资源的永久排除协议、使用示例及兼容边界。

绑定的 `"idempotency"` 包含 `"protocol"`, 非空 `"scope"`, 稳定 `"key"`, 以及明确的 `"valid_through"`.
`"valid_through" => nil` 表示无期限保证, 缺少字段会拒绝. 有限保证还须声明资源协议真实执行
`"expiry_enforced" => true`, 确保过期后到达资源的旧 key 请求不会重新产生效果;
仅本地调用前看时钟或服务缓存存在一段时间不足以满足条件。显式接受重复风险的尝试保存独立依据，
不依赖旧幂等保证仍然有效；资源/账户匹配和尝试预算继续执行。

有限幂等的恢复命令需要上下文中的 `contract_time`: 它和 valid_through 使用同一可信资源协议时间域,
独立于 lease 的 `now`; 边界 `contract_time <= valid_through` 有效. 缺少可信时间或无法重验时拒绝危险重试.
后续尝试的替代, 授权和 `Domain.check_invocation/3` 分别核验, 新 binding 的较长窗口不能延长原保证.
Worker 调用前还须核验当前 incarnation, 单 grant 最多调用一次, 以及实际资源匹配; 这些执行检查由 Runtime/Worker 实现.

`Report` 的 Worker 来源携带原 `token`. callback/query 来源使用 `source: %Beamlet.Report.Source{...}`,
`token` 留空; source 包含 kind, collection, intent_id, execution_id 和原 completion/query binding.
Adapter 先按版本化协议核验账户/签名/事件身份, 核心再精确核验原绑定, Operation 和值域.
已替代/已 Closed/lease 失效不撤销合法来源, 但旧 Success 只保留为证据, 不直接成为当前 Outcome.
报告身份使用来源作用域和稳定 report ID; 同内容重投不重复 History, 跨来源矛盾也保留冲突.

query 可以给出 NotFound 或 NotExecuted. NotFound 仅保留证据, 不改变 Unknown/Waiting 或推导未执行. NotExecuted 另需
`%Beamlet.Exclusion{authorization: original_token, query_binding: original_query, evidence_ref: stable_ref}`;
它只能由已核验外部排除保证的可信 Adapter 构造, 不能从不可信正文的布尔值复制. 本核心不验证真实外部 fencing. 确定
Knowledge 保留首份确定报告: 后来的 NotExecuted 不自动替换 FailureKnown, NotExecutedKnown 也不能仅凭后来 Failure 报告接受
Failed. [Quint 对照记录](../../model/implementation-conformance.md) 说明检查范围. 已存当前 Failure 在窗口后来失效,
或旧未知风险得到解释后, 可以重新发出 StopKnownFailure; 重复原报告只补确认, 不隐式重新进行策略终结.

## 可运行的领域路径

在 `apps/beamlet` 目录运行 `iex -S mix`, 然后执行:

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

# 这里仅提供示例证据. 实际 Worker 须取得已提交授权, 核验调用条件, 再在事务外调用 Handler.
:ok = Domain.check_invocation(authorized.intent, token, context)
report = %Report{id: "response-1", token: token, operation: "api.request.v1",
  kind: :success, body: %{"answer" => "hello"}}
{:ok, completed} = Domain.transition(authorized.intent, {:record_report, report}, context)
completed.intent.outcome
# %Beamlet.Outcome{kind: :succeeded, value: %{"answer" => "hello"}, ...}
```

## 验证与规格对应

在 `apps/beamlet` 目录运行 `mix test --warnings-as-errors`, 或在根目录运行完整 `mix test --warnings-as-errors`.

| 规格 | 代码测试覆盖 |
| --- | --- |
| [持久值与消息](../../model/spec/persistent-values-and-messages.md) §1–3 | 数值/Unicode/规范字节, 预算边界, 定义相等, keyed 重投与冲突 |
| [存储命令](../../model/spec/storage-command-contracts.md) §2–4 | 领取响应丢失/重投, 竞争顺序, 原 grant, 到期拒绝增量, 计数/时间溢出 |
| [核心状态机](../../model/spec/core-state-machines.md) §2–6 | Open/Closed, Unknown, Pending, Resolved, 冲突与迟到证据, 成功/失败/取消 |
| [lease 与权限](../../model/spec/leases-and-permissions.md) §3–5 | incarnation/generation/token 作用域, expiry 相等, 回拨不复活, lease 与结果资格分离 |
| [Handler 与恢复](../../model/spec/operation-handler-contracts.md) §4–7 | 未授权/外部排除/幂等三类依据, 原窗口三阶段检查, RetryOnce, StopKnownFailure, callback/query 作用域及跨来源冲突 |

这些是纯规则的行为测试. 竞争顺序测试不替代真实 SQL 并发、回滚、重启或持久性测试.
值规范表示接受已解码数据; wire decoder 还必须拒绝重复 JSON key, float/指数词法等无损解释问题.
Quint 源码和 SPEC 保持原语义, 本批实现没有修改模型来迁就代码.
