# 证据协调与持久命令

领域层 `Beamlet.Reconciliation` / `Beamlet.Judgment` 已接入本地 Authority SQLite：
旧结果采用、逐报告冲突处置、证据排除、部分取代和范围撤销。
对应 Quint `logic/{judgment,dispositions,reconciliation,commands,rules}.qnt`，
不删除原报告，不清除历史冲突，不改写已接受 Outcome。

## 原始事实与当前判断

`Execution.result` 仍保存首次确定 Knowledge，`Execution.conflict` 仍为历史粘性标志。
`Judgment.knowledge(intent, execution_id)` / `no_conflicts?/1` 根据当前适用处置解释证据，
恢复、后续授权、普通失败停止和协调终结使用这个当前判断。

每个已接受决定保存原提案、接受时 base/revision 及核验时 Policy。
base 包含 phase/current、全部原报告以及各 Execution 的存在性、phase、authorization、
原 Knowledge 和 conflict；不包含临时 lease、命令缓存、拒绝审计。
新证据或协议投影变化使旧处置不再适用，但保留原记录及所有权关系。

`Intent.judgment_revision` 仅在判断 view（base＋决定序列）改变时增长。
普通 claim/renew、无投影变化的 lease 到期、拒绝审计及重投不增版。
报告存入与终结可在一次 SQL 提交中分别增长；它不是 Storage 的提交 revision。
新提案引用精确审查版本；处理时不自动刷新 revision 或 supersession。

## 决定种类与守卫

| kind | 作用 |
| --- | --- |
| `:adopt_success` | 可采用合格旧 Execution 的成功；需要所有历史冲突都已覆盖 |
| `:adopt_failure` | 只采用 current 的失败；仍须排除授权未知风险和未解释旧成功 |
| `:exclude_from_judgment` | 依据核验过的契约排除指定成功证据；不终结 |
| `:exclude_all_evidence` | 逐项排除本次覆盖的全部证据；可恢复为未知，不终结 |
| `:withdraw_disposition` | 仅撤销明确引用的当前处置范围；不替换处理、不终结 |

有冲突时，evidence 必须覆盖所有历史冲突 Execution 的全部已存报告和主报告，每份恰好一项。
不是只挑有利的 Success，也不能因某规则已登记就省略覆盖或契约核验。
逐项格式为 `%{report: exact_report, treatment: :keep | :exclude,
basis: :verified_completion | :contract_exclusion}`。
保留的同尝试结果必须一致；全部排除后当前 Knowledge 为未知，
不能退回原始缓存 Knowledge，也不能因此推断已授权工作不会执行。

actor 为 `{:operator, principal}` 或 `{:rule, semantic_id, semantic_version}`。
这些身份均为显式文本，版本不是 Handler 发布版本或 Caller planner 的 rule 字段。

## 构造提案与命令

已有可信本地 Coordinator `c`、Intent ID `id` 和已存完整报告 `report` 时：

```elixir
alias Beamlet.Reconciliation
alias Beamlet.Reconciliation.Command

{:ok, facts} = BeamletRuntime.Coordinator.read(c, id)
{:ok, decision} = Reconciliation.propose(facts.intent, %{
  kind: :adopt_success,
  report: report,
  actor: {:operator, "operator-1"}
})
{:ok, command} = Command.new("review-2026-01", decision)
BeamletRuntime.Coordinator.reconcile(c, id, command)
```

propose 捕获当前 judgment_revision，规范排序 evidence，并自动计算新处置需要取代的原所有者。
构造不代表已经合格；SQL 内会重新检查。新命令不得自动使用更晚的 ReadFacts 刷新原提案。
命令 ID 为 Intent-local，采用、排除、撤销共用身份空间。

部分撤销需明确指定：
`supersedes: [%{decision_index: 0, reports: [original_report]}]`。
decision_index 是该 Intent 的持久 append-only 决定序号，从 0 开始，不是 History revision。
新处置必须完整引用所影响报告的当前历史所有者，即使旧处置因新证据暂不适用。
撤销只移除指定所有权，不恢复更早已取代的旧处置，不影响未提及范围。

列表表示有限集合，构造时规范排序；重复项拒绝。
每个 evidence/reference/Policy 集合最多 256 项，单报告正文仍受受限值预算约束。
整体命令/决定/旧结果随 Authority snapshot 保存，仍受 16 MiB 快照容量上限保护；
容量或数据库错误不能作为 Failed 或未执行的证据。

## 可信核验入口

默认 `Coordinator.reconciliation == nil`，入口返回 `:reconciliation_disabled`。
应用显式配置 arity-3 verifier：

```elixir
alias Beamlet.Reconciliation.Policy

verify = fn _intent, command, context ->
  same_principal = command.decision.actor == {:operator, context.actor}
  # 只演示手动采用已存的合格完成；冲突排除需要另外核验 Operation 契约。
  policy = %Policy{operators: ["operator-1"]}
  {:ok, policy, %{may_submit: same_principal, may_read: true}}
end

c = %{c | actor: "operator-1", reconciliation: verify}
```

verifier 在 SQL 取得保护、读取最新 Intent 后调用，只能做有界本地核验，不得联网、调用 Provider
或执行其他外部副作用。它必须绑定实际 principal/规则身份、Intent 作用域和当前权限，
返回 Authority 已核验的 Policy，不能从 command 复制“允许排除”“已验证”等断言。
远端证据核验应在事务外完成，再在保护内核对其固定引用及适用条件。
Coordinator 是可信本地 capability；这个接口不是通用 ACL/远端身份协议。

Policy 字段：

| 字段 | 可信事实 |
| --- | --- |
| `operators` | 当前合格的操作主体 |
| `registered_rules` | 精确语义版本及允许 kind、query/evidence 条件 |
| `excludable` | 已核验可排除的完整原报告 |
| `resolutions` | 已核验的完整逐报告处置集合 |
| `withdrawals` | 已核验的精确取代引用集合及撤销依据 |

规则条目精确格式：
`%{id: "r", version: "v1", kinds: [:adopt_success],
query_required: true, evidence_required: true}`。
精确版本须唯一匹配；同引用的矛盾定义拒绝新决定。
普通退役由可信 Policy 不再提供该版本表达：阻止新决定，不改 Intent、不增 judgment revision、
不删除旧已接受处置，也不妨碍有读取权限的原命令重放。
本实现保存接受时规则快照，但没有持久规则登记服务、发布/退役管理 API 或控制面认证；
Policy 的语义正确性与版本连续性由部署提供，不能把测试 fixture 当成真实业务排除协议。

## 提交、拒绝与重投

`Coordinator.reconcile/3` 返回 `{:ok, %Storage.Commit{reply: reply, ...}}` 或错误。
可读结果为：

- `{:committed, %Record{}}`：原决定索引及原 Outcome；非终结命令的 result 始终为 nil。
- `{:stale, %Record{}}`：原拒绝时的 judgment revision/view。
- `{:ineligible, %Record{}}`：明确领域拒绝。
- `{:command_identity_conflict, command}`：该身份已经保存不同原请求。

新合格命令将决定、命令、可能的 Outcome 和 History 同事务保存。
已获准提交但领域不合格时，拒绝身份与审计也同事务保存；后来权限/依据改善不重判该身份，
需要重新审查并使用新 ID。提交权限拒绝、结构错误、数据库故障不消耗一个成功的领域命令记录。

相同命令重投先返回原记录，不重新应用，不重验旧版本、不按后来的 Outcome 改写原 result。
权限每次重新核验：允许提交但禁止读取时仍可提交，Coordinator 仅返回
`{:error, :command_forbidden}`，不泄露 Commit.facts/events；
以后允许读取而禁止新提交，仍可恢复原结果。底层 SQLite/Domain 是可信内部 API，
它们返回完整提议/快照，不应绕过 Runtime 暴露给不可信客户端。
通用 Coordinator.read 同样仍是可信应用能力，不由这个 verifier 自动保护。

## 存储升级与验收

内部 Codec 新写 version 2，继续读取原 version 1。
旧 Intent 精确字段集合补入 `decisions: [], commands: %{}, judgment_revision: 0`，
从导入事实开始建立新的审查基线，不伪造历史判断变化。
已有 reports/grants/Outcome/History 保持；下一次实际写入保存 version 2。
不完整 v2、未知字段/类型/原子/版本拒绝。不支持旧程序与新程序混合写入或降级。

18 项领域验收、13 项真实 SQL/Runtime 验收覆盖采用、失败风险、全覆盖、全部排除、
新证据失效、部分撤销、规则退役、命令身份/原结果、权限、并发、重启、
历史故障回滚、只读数据库和旧快照升级。
另有直接 Quint oracle：2,048 组命令＋144 组撤销组合；
这些是选定前缀及有限输入集合的对照，不是任意 SQL/Runtime 轨迹的穷尽证明。
