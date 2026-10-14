# Quint 与当前实现的对应记录

当前实现以首版 `beamletExecution` + `normalUseProfile` 为依据, 配合首版 SPEC 的工程义务.
对照后已修正下述差异; 已实现领域子集通过本文列出的直接对照和回归检查.
这不是 Elixir/SQL 的完整 refinement 证明, 也不表示整个 `model/` 均已实现.

## 状态与动作映射

| Quint 定义 | 当前代码 / 行为 |
| --- | --- |
| `Ledger.phase/current/attempts/outcomes` | `Intent.phase/current_execution_id/executions/outcome` |
| `Attempt.knowledge` / `judgmentKnowledge` | `Execution.result` 的首份确定报告; Pending/NotFound 不提供确定 Knowledge |
| `Attempt.negativeSeen` | 由保留的 NotFound 报告集合导出, 不另存布尔字段 |
| `canCreate/applyCreate`, `canClaim/applyClaim` | Domain create/claim; storage expected generation 重投协议额外对应 `contracts/claim.qnt` |
| `canAuthorize/applyAuthorize`, `canRenew`, `canExpire/applyExpire` | Domain authorize/renew/expire; 到期拒绝作为可提交的屏障返回 |
| `reportSourceValid`, `sameReportIdentity`, `applyReport` | Report 来源/绑定核验与 Domain 报告去重、冲突、投影 |
| `safeToReplaceWithEvidence`, `canReplaceWithEvidence` | Recovery.basis/replacement_allowed + Domain ReplaceExecution |
| `ordinarySourceEligible`, `recordAndMaybeCommit` | 当前成功原子终结; Failure 另受策略、Knowledge、旧成功和未知风险守卫限制 |
| `stopRequired`, `retryHandlerQualified`, `normalStop` | RetryOnce, 原幂等窗口三阶段检查, StopKnownFailure |
| `ByCallback` / `ByQuery` | 独立 Source, 不借用 Worker lease token 作为第三方认证 |
| `contracts/history.qnt` 原子提交 / 重复报告 / 次序 | SQLite 的 immediate 事务, 唯一 Outcome, revision/position History |
| `discoverWork`, `readFacts` | SQLite 候选扫描和一致快照; History 分页固定在已读 revision |

细化边界: 标识符从小整数扩展为 UTF-8 文本, Report 正文从小整数扩展为受限值 v1.
SQL/Runtime 额外保存可信 binding, 排除证明引用, 完整 Intent 来源域和版本化存储格式.
首版只有两个 Execution 的模型域, 实现显式执行“最多两个已建立尝试”预算.

有意收窄: 普通替代及后续授权遇到任意未协调冲突时拒绝; query 须具有原授权保存的可信 query binding.
有限幂等只接入具有资源侧过期拒绝保证的协议, 不实现其他时钟误差/网络延迟界方案.
这些收窄不授予模型以外的危险执行权限, 但不能据此宣称所有模型允许的动作都已实现.

## 此次发现并修正的差异

1. 原实现看到后来 NotExecuted 的排除材料就改变重试依据. 模型 `applyReport` 保留首次 Knowledge;
   FailureKnown 不因后来 NotExecuted 自动成为 NotExecutedKnown. 已改为按首份确定投影评估安全依据.
2. 原实现只检查当前 Failure 原始报告, 可能在 NotExecutedKnown 下接受 Failed.
   模型 `ordinarySourceEligible` 明确要求 FailureKnown. 已加入该守卫, 保留原证据而不制造终结.
3. 原实现已冲突后接收一个未新增矛盾的报告时, 未继续追加冲突 History.
   模型 `applyReport` 的 conflict 是粘性的; 已对齐后续新报告的冲突审计.

没有修改现有 Quint/SPEC 的规则来迁就代码.

## 可复现检查

直接对照在 `apps/beamlet` 运行:

```sh
mix run ../../scripts/check_domain_conformance.exs
```

脚本复制当前 Quint 源码到临时目录, 原样导入现有纯函数作 oracle, 不重写一套预期守卫.
穷举选定 10 种 Worker/query/callback 报告的三步顺序, 分别复用或分配 report ID, 共 2,000 组.
比较 Knowledge, 生命周期, 粘性冲突, 报告数, History 增量数, 成功终结,
无幂等的替代依据和 Failure 来源资格. 每次输出原始 ITF 路径, 遇到差异立即失败.
该范围覆盖同/异来源、同身份改内容、重复、NotFound、NotExecuted、Pending 和结果值冲突,
不等于所有任意长度轨迹或 SQL 执行的穷尽检查.

此次检查结果:

- 直接 Quint/Elixir 对照: 2,000 组全部通过.
- 既有 Quint 确定场景: 全部 13 组、360 个场景通过; 日志在 `/tmp/beamlet-implementation-quint-tests/`.
- `beamletRecovery` 从 `retryAuthorizedInit` 采样 100 条, seed=42, 最多 100 步: 未观察到 safety 反例;
  Success/Failed 各有 5 条见证, `policyStopWitness` 为 0. 后者不能从本次采样声称覆盖,
  StopKnownFailure 另由既有确定场景及 Elixir 回归测试检查.
- 新增两条 Knowledge 顺序回归, 修改前均能复现失败, 修改后通过.
- SQLite 与 codec 新增 23 个真实文件/序列化测试; 详见 [Storage 说明](../apps/beamlet_runtime/README.md).

根目录 `mix test --warnings-as-errors` 包含领域、Storage 与其余应用测试; Quint 场景需另跑 `mix quint test`.
没有执行 Apalache 验证或建立自动化无界 refinement 证明.

## 仍在模型而不在产品实现中的部分

协调/治理, conflict disposition, rule retirement/withdrawal, 可靠传输与确认流程,
实际 Worker incarnation/每 grant 单调用的执行循环, Handler/resource 登记与真实验签,
Agent manifest/多依赖 continuation, 外部 CAS/receipt, PostgreSQL 和真实掉电验收尚未实现.
这些模型提供后续设计与验收依据; 现有模拟通过不能当作这些工程部分已经完成.
