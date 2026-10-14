# Quint 与当前实现的对应记录

当前实现以首版 `beamletExecution` + `normalUseProfile` 为依据, 配合首版 SPEC 的工程义务.
对照后已修正下述差异; 已实现领域子集通过本文列出的直接对照和回归检查.
这不是 Elixir/SQL 的完整 refinement 证明, 也不表示整个 `model/` 均已实现.

## 状态与动作映射

| Quint 定义 | 当前代码 / 行为 |
| --- | --- |
| `Ledger.phase/current/attempts/outcomes` | `Intent.phase/current_execution_id/executions/outcome` |
| `Attempt.knowledge` / `judgmentKnowledge` | 原始 `Execution.result` 保留首份确定报告；`Judgment.knowledge/2` 解释当前适用处置；Pending/NotFound 不提供确定 Knowledge |
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

query 须具有原授权保存的可信 query binding。早期实现曾额外要求重试前解除全部冲突；
本轮已移除该收窄，安全替代与终结资格分别核验，详见下方重复风险／fencing 增量。
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
该阶段只实现单 collection 的本地 await-all；后续单步 decision/Continuation 增量见下文。自动 Agent loop、远端 ACL 和跨存储恢复证明未提供。

19 个 Caller 测试包含独立 Repo 并发和真实只读 SQL 故障；
验证 Authority 已接受、调用方未存关联时仍按原身份恢复，而不把 SQL 错误当 Failed。
该套是公开接口工程验收，不是 Caller 动作的自动轨迹 oracle；现有 2,000 + 896 组 oracle 仍只覆盖前述领域子集。
本增量完整 umbrella 重跑 225 个测试/文档测试通过；19 个 Caller 测试以 seed=1/42 重跑通过。
Quint 多 Intent 42 个、三依赖 10 个确定场景重新执行通过；未在本增量全量重跑其他组、mutation 或历史采样预算。

## 单步持久决定 / Continuation 增量

`Caller.decide/read_decision/discover_decisions/register_next/advance_next` 实现 SPEC §8 的固定单成功来源推进。
已收集 A 的 Succeeded 可以驱动 C，原 A/B round 未收齐时继续保持未完成。
消费原完整 Outcome、规则版本、选择值、后续 key/定义一起保存在调用方 schema v2；
Domain、Authority Storage 和 Quint 规则未修改。

| Quint 条件 | 实现及工程验收 |
| --- | --- |
| `sourceQualified`, `decisionSourcesSound` | 只消费原 slot 的已收集 Succeeded，SQL 内复核 slot/Intent/完整 Outcome；C 输入等于原业务值，不使用通知/报告 |
| `applyDecide`, `decisionStable` | owner/computation/step 唯一身份、不可变决定及 SQL update 拒绝；首次提交生效，重投不运行 planner |
| `canRegister`, `manifestMatches`, `nextManifestSound` | 决定先提交，再从原记录建立 C 清单；保留后续 round，错误清单拒绝，已有 round 不追认为新决定 |
| `requestReady`, `dispatchOrdering` | advance_next 成功建立清单后才 submit；决定/注册写故障不发送 C |
| `recoveredManifestWitness`, `recoveredSuccessorWitness` | 决定/清单保存后重启、C 接受回复丢失、Closed 结果复用；不按 sent 内存标记跳过 |
| 原 round 的 `toolRoundsSound` | 原 B 未终结不因 A 决定而完成；B 迟到不覆盖消费集合或重算 C |

工程扩展与限制：模型固定一步及整数身份，当前实现支持显式文本 computation/step 及一次调用一个后续依赖。
它并未验证任意多步循环。选择内容为额外受限值诊断/业务材料，不影响 C 输入的固定传递守卫。
已有决定身份采用明确的“先提交者生效”策略；并发 planner 可能计算多次，后提交者返回原记录。
独立 Repo 竞争测试是模型之外的工程验收，不宣称 Quint 检查了多个并发调用方实例决策。
已持久保存的结果缓存仍依赖原 Authority 历史连续性，不解决回滚/克隆或外部业务代码 exactly-once。

20 个新集成测试覆盖各提交/退出窗口、进程强杀、原身份恢复、B 乱序完成、真实只读 SQL 故障和 v1→v2 迁移。
首条部分推进验收在实现前失败，接口完成后通过。新程序要求先执行迁移；
v1/v2 混合写入不受支持，旧程序不能绕过新版后续保留检查而仍宣称 Continuation 保证。
本轮完整 umbrella 245 个测试/文档测试通过；20 个 Continuation 测试以 seed=1/42 重跑通过。
Quint `continuationTests` 25 个场景以 `--seed 42 --max-samples 1 --backend rust` 重新执行通过。
未将无 seed 的默认每个随机测试 10,000 次预算算作完成；不声称本轮全量重跑其他模型组或 mutation。
强制编译、严格 Credo、格式/diff、变更文件主动 LSP 及 README 两段示例实际运行通过。
这是有限接口验收，不是 Caller/SQL 的自动 refinement 证明。

## 共享资源 CAS / receipt 增量

`Object.Store` / `Handlers.SharedObject` 实现独立 SQLite 逻辑对象资源，
Operation 为 `object.replace_if_version.v1`；不是普通文件系统或 SPEC 示例 file Operation 的内置驱动。
输入直接保存受限 content，详见 [共享对象协议](../apps/beamlet_runtime/OBJECTS.md)。
Domain、Authority Storage 和 Quint 模型未修改。

| shared 模型条件 | 资源实现和验收 |
| --- | --- |
| `sameObjectKey`, `objectReceipt` | service instance/account/object/operation/collection/Intent 作用域；原完整请求比较；重复返回原 receipt，异请求拒绝 |
| `applyObject`, `objectWritesSound` | immediate 事务内 CAS + 内容/版本 + receipt；两个初始版本请求只写一次；receipt 插入故障使写入回滚 |
| `versionMismatchIsSuccessfulBusinessResultTest` | applied 与 version_mismatch 都返回 Success，版本不匹配不重写对象 |
| `objectEvidenceSound`, `queryObject` | query 只接受原请求 receipt，receipt_ref 稳定；没有 receipt 则 NotFound，无 NotExecuted/Failure 推断 |
| `externalCommitDoesNotImplyOutcomeTest` | 资源提交与 Authority 独立，丢弃 invoke 回复时 Intent 仍 Open，通过原查询接受 Outcome |
| `workerLossRecoversOriginalReceiptTest`, `authorityRestartAfterResourceWriteTest` | Worker/Authority/资源完全重启，保留原 instance/binding/receipt，新会话不调用旧 grant |
| `newExecutionReusesOriginalResourceReceiptTest` | 安全替代沿用 Intent key/原 scope，读取原 receipt，不重新进行 CAS 或覆盖后续写入 |

工程细化：请求身份和内容为文本/受限值，资源可包含多个显式 account/object 和多个版本更新；
模型固定两个 Intent 竞争初始版本，不能外推其已穷尽任意更新历史。
Scope 中明确包含 collection，避免不同 Authority 域的相同局部 Intent ID 串键。
每个数据库有持久 instance，防止同名新库继承原保证；仍不解决克隆/备份回滚。
无 callback/Pending/NotExecuted/外部停止声明；有限幂等窗口、第三方认证/文件协议仍未实现。

18 个真实资源/Authority SQLite 测试及 seed=1/42 重跑通过，
含实际只读故障、receipt INSERT 回滚、不可变历史、版本上限和原请求精确重投。
完整 umbrella 本轮 263 个测试/文档测试通过；共享资源 Quint 10 个场景以 seed=42/max-samples=1/Rust 重跑通过。
严格 Credo（64 个源码文件）、格式/diff、五个变更 Elixir 文件的主动 LSP 检查通过；
共享资源 README 示例实际执行，验证两个竞争 Outcome 和原身份重提交结果复用。
既有直接 oracle 不因此自动覆盖本资源 SQL；本次是具体协议的有限工程验收，不是全量 refinement 证明。

## 证据协调、规则资格与持久命令增量

`Beamlet.Judgment` / `Reconciliation` 实现完整决定种类及当前解释，
`Coordinator.reconcile/3` 在 SQL 保护内接收可信 verifier 的 Policy/access。
原始报告/Knowledge、历史冲突及已接受 Outcome 不可覆盖。
详细接口与部署前提见 [协调说明](../apps/beamlet_runtime/RECONCILIATION.md)。

| Quint 函数 / 协议 | 实现与验收 |
| --- | --- |
| `judgmentBase/View`, `advanceJudgment` | 独立判断版本；续租/命令缓存/拒绝审计不增版；报告及终结可分别增版 |
| `canReconcile`, `applyReconcileAndMaybeCommit` | 核验原完整报告、主体/精确规则版本、契约、全覆盖及取代引用；决定/Outcome/History 同 SQL 提交 |
| `judgmentKnowledge`, `noConflicts`, `noUnresolvedRisk` | 当前解释与历史事实分开；全部排除恢复未知，不能消除授权未知风险；恢复/停止使用当前判断 |
| `requiredSupersessions`, `advanceBindings` | 显式原所有者、部分取代/范围撤销，不恢复更早处置；新证据使适用性失效但保留所有权 |
| `processCommand`, `commandReplyWithAccess` | 接受/明确拒绝共用稳定 ID；原请求/原结果不可变；提交/读取权限分开；Runtime 隐藏不可读 Commit |
| `registeredRuleQualified`, 普通 retirement | 按受信 Policy 的精确语义版本/条件核验；退役不改旧记录、绑定、判断版本或重放结果 |

模型注册/核验事实由可信 Policy 输入提供，本轮没有实现独立持久治理登记/退役服务或远端认证。
SQL 快照保存接受时 Policy，供解释历史；不从请求方断言制造真实契约排除依据。
Policy/evidence/reference 集合限制 256 项，总快照仍限制 16 MiB，容量故障保守返回错误。
该协调阶段 Codec 新写 v2（当前 v3 见下文），精确兼容原 v1 Intent 字段并补入空决定/命令及判断版本 0；
旧报告/grant/Outcome/History 不变，v2 缺字段拒绝，旧/新程序混写不受支持。
`Recovery.basis/3` 现在必须带 Intent，避免在协调后依赖已排除的原始 Knowledge。

直接对照脚本（在 apps/beamlet 运行）：

```sh
mix run ../../scripts/check_reconciliation_conformance.exs
```

原样导入既有 Quint `beamletCore` 函数，不改模型规则：
2,048 组＝4 种决定 × 2 种冲突前缀 × 4 种证据集合 × 4 种主体/规则版本
× 2 种核验依据 × 2 种审查版本 × 4 种权限。
比较资格、处理/只读重投结果、决定/命令数量、判断 revision、History 数、Outcome、
当前 Knowledge 与冲突解除资格。
另有 144 组＝3 种撤销范围 × 3 种引用模式 × 2 种核验依据 × 2 种审查版本 × 4 种权限，
比较范围撤销资格、原结果重放、剩余绑定、判断版本/Knowledge/冲突和审计。
共同前缀在模型使用 ALLOW_REPEAT=true，在代码用原无期限幂等契约安全替代；
该阶段对照尚未覆盖风险接受入口；后续增量已实现并另做直接矩阵对照。

本轮新增 18 个领域、13 个真实 SQL/Runtime 验收，seed=1/42 重跑通过。
完整 umbrella 294 个测试/文档测试通过；原 2,000＋896 组对照继续通过。
Quint repeatingTests 79、conflictTests 81 场景以 seed=42/max-samples=1/Rust 重跑通过。
这些组含规则/退役/取代/撤销场景；未重跑全部模型组、mutation 或历史随机预算。
强制编译、严格 Credo（72 个源码文件）、格式/diff 和 16 个变更 Elixir 文件的主动 LSP 检查通过；
协调 README 的可信 verifier、旧成功采用与命令重投示例实际运行通过。
不将有限矩阵与进程/数据库故障测试声称为完整 Runtime/SQL refinement 或无界证明。

## 重复风险、fencing 与 SQL 轨迹增量

原 Definition 新增严格布尔 `repeat_accepted`，默认 false；同 Identity 异接受值为定义冲突。
对应模型固定 ALLOW_REPEAT 在单 Intent 上的显式细化，保存 `:repeat_accepted` 替代依据，
授权/调用重验原定义；不依赖原幂等窗口，不增加两次预算，不改变终结证据守卫。
去除 Recovery 上额外的“所有冲突先解除”限制，按模型分别检查替代安全、启动资格及终结资格；
旧报告/Knowledge/conflict/Outcome 不覆盖。

`Handlers.FencedObject` 的独立 Operation `object.fenced_replace_if_version.v1`，
在对象 schema v2 将原 Execution/full token/request 的排除记录与资源调用按 immediate 事务串行化。
先执行则恢复 Success；先排除则旧授权永远不能执行，新授权可凭 query 的原 NotExecuted 安全替代。
资源排除提交与 Authority Report Stored 独立；原 CAS Operation/协议不冒充新增能力。
它不声明 idempotency；正常逻辑请求 receipt 仍保留。详见 [协议与示例](../apps/beamlet_runtime/FENCING.md)。
Codec 新写 v3，读取 v1/v2/v3，旧 Definition 仅导入默认拒绝风险；v3 缺字段/非布尔值拒绝，
原 v1 Intent 的零版本基线兼容保留。不是旧/新程序混写或降级保证。

本轮直接对照：
- 2,000 组报告；原 896 组严格重试扩到 1,568 组，新增 672 组带冲突；
  另以 ALLOW_REPEAT=true 运行相同 1,568 组风险接受组合。
- 原协调 oracle 的 2,048 组命令＋144 组撤销重新通过。
- `mix run scripts/check_resource_conformance.exs` 原样导入 Quint 纯状态函数，
  在真实双库执行 2 条轨迹／30 个检查点：授权、排除、丢回复、双库重启、query、
  替代、第二次授权／资源提交、取消竞争、迟到报告、重复确认。
  比较 phase/current、原 Knowledge、判断 revision、报告数、冲突、Outcome、资源版本与原排除记录。
  同步资源 IO 以已提交业务结果投影；不验证资源内部全部交错、完整 Worker 消息网络或 Caller 图。

新增 3 项领域、11 项 fencing、1 项 Runtime 风险恢复及 1 项 Codec 兼容验收；
定向 seed=1/42 及完整 umbrella 310 个测试/文档测试通过。
Quint fencedTests 2、strictTests 23、repeatingTests 79 个场景以 seed=42/max-samples=1/Rust 重跑通过；
不将曾超时的组合运行算作成功，repeatingTests 已单独重跑完成。
强制编译、严格 Credo（77 个源码文件）、格式/diff、18 个变更 Elixir 文件的主动 LSP 检查通过；
fencing README 示例实际执行通过。完整回归曾出现旧执行测试临时目录清理失败，目录改为 UUID 后完整 seed=42 重跑通过。
有限轨迹不构成无界 refinement 证明。

## 剩余工程与验证缺口

ALLOW_REPEAT 和本地 CAN_FENCE 协议已有具体实现；第三方资源仍须提供自己的真实排除协议。
协调/处置/规则版本核验/退役语义/范围撤销已有本地实现，独立治理登记/发布/退役控制面仍缺。
跨设备传输与认证/权限、真实 Provider 的验签/查询/排除保证、普通文件/API 的 CAS/receipt、
PostgreSQL 和真实掉电验收，以及完整 Agent loop/任意多来源多步决策仍需工程实现与验收。
本地数据库对象 CAS/receipt 已实现，不代表其他资源具有相同保证。
这些模型提供后续设计与验收依据; 现有模拟通过不能当作这些工程部分已经完成.
