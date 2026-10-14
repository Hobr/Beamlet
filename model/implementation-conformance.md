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

脚本复制当前 Quint 源码到临时目录, 原样导入 `normalUseProfile` 导出的既有纯函数作 oracle, 不重写一套预期守卫.
穷举选定 10 种 Worker/query/callback 报告的三步顺序, 分别复用或分配 report ID, 共 2,000 组.
比较 Knowledge, 生命周期, 粘性冲突, 报告数, History 增量数, 成功终结,
无幂等的替代依据和 Failure 来源资格. 每次输出原始 ITF 路径, 遇到差异立即失败.
该范围覆盖同/异来源、同身份改内容、重复、NotFound、NotExecuted、Pending 和结果值冲突.
另穷举 4 种旧尝试依据（Failure、未授权、NotExecuted、Unknown）× 4 个原窗口 × 4 个新窗口 × 2 个协议关系 × 7 个契约时刻,
共 896 组, 直接对照 `idempotencyValid`、`canReplaceWithEvidence`、`retryHandlerQualified`.
代码比较原保证、替代资格、授权资格及已保存 grant 的调用前重试守卫. lease 时刻固定以隔离契约窗口,
不假定替代时安全就永久可调用, 不将该矩阵称作 Worker/SQL 任意长度轨迹的穷尽检查.

已完成的检查记录（包含此前阶段，非每次均全量重跑）:

- 直接 Quint/Elixir 对照: 2,000 组报告与 896 组重试协议组合全部通过.
- 既有 Quint 确定场景: 全部 13 组、360 个场景通过; 日志在 `/tmp/beamlet-implementation-quint-tests/`.
- `beamletRecovery` 从 `retryAuthorizedInit` 采样 100 条, seed=42, 最多 100 步: 未观察到 safety 反例;
  Success/Failed 各有 5 条见证, `policyStopWitness` 为 0. 后者不能从本次采样声称覆盖,
  StopKnownFailure 另由既有确定场景及 Elixir 回归测试检查.
- 新增两条 Knowledge 顺序回归, 修改前均能复现失败, 修改后通过.
- SQLite 与 codec 新增 23 个真实文件/序列化测试; 详见 [Storage 说明](../apps/beamlet_runtime/README.md).

根目录 `mix test --warnings-as-errors` 包含领域、Storage 与其余应用测试; Quint 场景需另跑 `mix quint test`.
没有执行 Apalache 验证或建立自动化无界 refinement 证明.

## 本地 Runtime 增量

本地执行沿 RFC 0001 §5/§7 与 SPEC runtime-architecture §2/§4 的边界继续实现;
Domain 和既有 Quint 规则未改变. 下面是工程行为对应, 不表示报告 oracle 已覆盖 Worker/SQL 的无界执行.

| 模型/契约 | 本地实现与验收 |
| --- | --- |
| `requestQualified`, `normalAuthorize`, `resendGrant` | Worker 领取/请求; Coordinator 只从已提交 Commit 交付 Grant; 原 token 重投返回原 binding |
| `canReceiveGrant`, `canCall`, `applyCall` | Worker 核对 scope/incarnation; 按完整 Execution scope 安装单次调用标记后派发 Task; 重复交付不重入 |
| `applyWorkerCrash/Restart`, `discardOldGrant` | 重启生成新 UUID incarnation, 不继承标记/许可; 已授权尝试不由新会话接续 |
| `contracts/resource.qnt` authorization/call guards | 静态 Registry; SQL 保护内重选 Handler/资源; 调用前再次核验实际环境; 不兼容时保留 Prepared/原等待事实 |
| `normalRecoveryActions`, `normalStop` | 持久候选分页重扫; 原关联查询; 保护内 expiry/停止/替代; 原窗口在授权/调用继续重验 |
| `pendingReport`, `applyPublish/Receipt`, `redeliverCallback` | Worker 原 Report 保留至 Commit; 可选 query/callback Adapter; 完成先于 Pending 不回退; 来源与正文改动保留冲突 |
| RFC/Storage 提交义务 | Repo 暂停错误不杀死持有待确认报告的 Worker; 同名 Repo 恢复后只重投报告; Handler/SQL 故障不制造 Failed |

细化选择: UUID 是 fresh incarnation 的工程表示, 依赖生成值不复用; 它不是持久 generation.
Worker 标记在 Task 派发前安装, Task 作为一次调用的在途工作, 不自动重启; 父进程退出不证明 Task/外部请求停止.
Worker 本地缓存不是权威事实, 崩溃丢报告后无查询/重投仍可 Unknown. 默认会话容量有界, 不清除旧标记来重复接受 grant.
本地 facade 是可信应用 capability, 不等于远端认证; HMAC/query Fixture 只检验 Adapter 入口契约, 不证明真实 provider 协议.

新增 44 个真实 SQLite 支撑的本地执行测试, 包括原 incarnation 在取消/expiry/Authority 离线后持原 grant 调用,
新 incarnation 拒绝旧 grant, 同 scope 重复/并发派发, 两 Coordinator 竞争, 原窗口失效阻止调用,
Resolved 失败在窗口失效后停止, 先完成后 Pending, 原 Worker 丢失后的原查询,
签名/账户/目标 scope/结果 schema 拒绝, 回执重投, 扫描回绕/重启与存储故障分类.
相同身份重提交在 Handler 下线后仍复用原 Intent/Outcome; 只在原子建立新 Intent 的分支执行当前 schema 校验,
不把当前部署缺失或新版校验套到已接受的旧定义上. 异定义仍按原定义拒绝.
这些测试保留外部副作用与持久事实之间的故障窗口, 没有增加无条件 exactly-once 或 Liveness 承诺.

## Runtime 守卫对齐补强

此次对照 `normal/actions.qnt` 和 `normal/logic.qnt` 发现并修正:

1. Registry 原先只取首个 Operation/资源兼容的发布, 首个发布的重试协议不合格时挡住后面的合法发布.
   新授权在 SQL 保护内按原 Domain authorize 守卫筛选候选, 最终决定仍由 Storage 再次执行原规则并提交;
   候选试算是纯计算, 不产生第二份授权/History. 原 grant 重投仍返回原绑定, 不重新选发布.
2. `normalCall` 在调用发生时重验原保证; Worker 原先只在 Task 派发前验证.
   现在 Task 调用 Handler 前再次采样契约时间并重验实际资源. 条件失效则不调用、无 Report/Failed,
   已安装单次标记保持, 不因保守放弃而允许同 grant 重入. lease 到期/取消仍不是资源 fencing.
3. query/callback 原先可能先运行 Adapter 再由核心拒绝未声明能力.
   现在按原授权 binding 检查 query/completion 能力后才运行 Adapter, 对应 `supportsQuery` / `supportsPending`.

三项主回归均先复现失败再通过; 另验实际资源在派发/调用之间改变,
及候选筛选不丢弃必须持久化的 expiry 拒绝屏障. 新能力不通过部署列表绕过原协议, 不修改 Quint/SPEC 来适配实现.
本次重新执行: 77 个领域测试、86 个 Runtime 测试/文档测试、61 个本地执行/审批测试以 seed=42 重跑,
49 个 Quint 正常使用场景、42 个多 Intent 场景, 以及 2,000 + 896 组直接对照, 均通过.
该阶段根目录完整测试尝试曾受并行 Web 的 eqrcode 依赖覆盖配置阻塞; 独立核心/Runtime、严格 Credo、格式与主动 LSP 检查已通过。
该阻塞在后续 Caller 增量的完整 umbrella 重跑时已不存在，不能视为当前仍阻塞。
未在本次重跑其他 Quint 组、全部 mutation 或历史模拟预算.

## 持久审批资源增量

`Handlers.Approval` / `Approval.Store` 实现 SPEC operation-handler-contracts §8.2 的一个本地细化:
授予 Start Authorization 前保留原关联, 独立资源库创建审批, 返回 Pending, 之后查询原请求产生 Success.
批准/拒绝都是业务正常完成, 与后置人工协调不是同一功能. 不修改 Quint 或核心领域规则.

| 规格/模型条件 | 资源侧工程实现 |
| --- | --- |
| `normalUseProfile` Pending/query 来源与恢复 | 授权 binding 保存 collection/Intent 及 query 协议; 资源请求与决定重启可读; Worker 退出不影响来源资格 |
| 原 idempotency key/scope 保持及 `retryHandlerQualified` | 资源 SQL 主键为 collection/Intent; 原请求严格比较; 永久保留请求/receipt, 替代复用同一请求 |
| `contracts/resource.qnt` 原目标匹配 | 保存服务 identity + 持久 instance, 同名新库拒绝继承 binding; 调用/查询重新核验原实例 |
| 资源事实与 Authority Knowledge 独立 | 两个 SQLite 文件及两个提交边界; 创建已提交但响应丢失仍可能 Unknown, 通过原查询补充证据 |
| `applyReport` NotFound 不排除执行, 结果/冲突不可覆盖 | missing/awaiting/decision 各自稳定观察 ID; 未决定仅 NotFound, 不构造排除证明; 迟到决定不会覆盖 Cancelled |

17 个真实数据库测试覆盖以上路径, 包含创建回复丢失、安全替代、并发建立/决定、资源服务与 Worker 重启.
共享 Worker 的两项审批故意使用相同局部 Execution ID, 核验 `multi/properties.qnt` 的 scopeIsolation/sharedSessionsSafe:
原 grant 不串域, 单次标记按完整 scope 分离, 一个 Outcome 不修改另一项事实, 新 incarnation 拒绝全部旧许可,
原 stable key 重建各 slot 后只复用各自结果. 此测试不实现调用方持久 manifest 或任意 continuation 逻辑.
资源服务只接收已认证的本地主体, 查询可信性来自受控 Repo capability; 不是通用第三方验签实现.
“永久幂等”依赖资源库不丢失/回滚且历史键持续保留. instance 不隔离克隆/旧备份, 数据保留与掉电保证仍是部署前提.
已有模型将外部资源协议作为可信条件; 本地 SQL 测试提供这个具体协议的有限工程证据, 不构成无界 refinement 证明.

## 持久调用方组合增量

`apps/beamlet_agent` 新增 `Beamlet.Agent.Caller`，对应 SPEC multi-intent-and-tool-calls §1–7，
不向核心 Domain 添加依赖图。调用方独立数据库保存稳定 round/完整清单、slot 关联与不可变结果汇总；
Authority 和调用方分别提交，没有跨数据库原子性。详细接口与示例见 [Caller 说明](../apps/beamlet_agent/README.md)。

| 模型条件 | 实现与验收 |
| --- | --- |
| `openRound`, `validDependencies` | 首次发送前持久保存完整清单；同 round 异定义拒绝；显式 slot + 非空 stable key |
| `resolvedFor`, `referenceSound`, `multiResolve` | 以原 Identity/Definition 提交并核对回复事实，按 slot 保存 Intent；owner 不隐含进入引擎身份 |
| `readDependency`, `resultSound`, `slotsUnique` | 只从 ReadFacts 保存完整 Outcome，验证 collection/Intent/定义及结果来源作用域；重复观察不填其他 slot |
| `allCollected`, `collectRound`, `toolRoundsSound` | 每项都有结果才持久保存完整 aggregate；同 Intent 占多个 slot 须明确声明 |
| `crashAgent/restartAgent`, 三依赖恢复 | 独立调用方库重启后读原清单；两项已完成不冒充第三项；Closed 重读不新建 Execution |
| `unknownIsolationWitness` | Unknown/错误/离线不制造 Failed；一个 Failed/Cancelled 不隐式取消兄弟 |

工程细化：关联和已核验结果缓存也持久保存，不直接映射为模型必须随 crash 清空的 `agentLocals`；
它们是额外调用方材料，依赖原 Authority 的不可变 Outcome/历史连续性。最终 aggregate 才对应 round.completed/results。
清单按 slot 规范排序；提前拒绝同 Identity 异 Definition 是保守收窄。
当前只支持单 collection 的本地 await-all，不提供自动 Agent loop、持久 decision、Continuation、远端 ACL 或跨存储恢复证明。

19 个 Caller 测试包含独立 Repo 并发和真实只读 SQL 故障；
验证 Authority 已接受、调用方未存关联时仍按原身份恢复，而不把 SQL 错误当 Failed。
该套是公开接口工程验收，不是 Caller 动作的自动轨迹 oracle；现有 2,000 + 896 组 oracle 仍只覆盖前述领域子集。
本增量完整 umbrella 重跑 225 个测试/文档测试通过；19 个 Caller 测试以 seed=1/42 重跑通过。
Quint 多 Intent 42 个、三依赖 10 个确定场景重新执行通过；未在本增量全量重跑其他组、mutation 或历史采样预算。

## 仍在模型而不在产品实现中的部分

协调/治理, conflict disposition, rule retirement/withdrawal, 跨设备可靠传输与认证/权限流程,
真实 Provider 的验签/查询/排除保证, 完整 Agent loop/持久 decision/多依赖 continuation,
外部 CAS/receipt, PostgreSQL 和真实掉电验收尚未实现.
这些模型提供后续设计与验收依据; 现有模拟通过不能当作这些工程部分已经完成.
