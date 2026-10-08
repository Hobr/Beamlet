# Quint 验证规范

## 1. 范围

使用能暴露错误答案的最小模型回答架构问题。主套件为 `spec/quint/core/`；大型探索套件只是补充。增加状态前先记录来源对应、接口前提与非目标。保留架构/ADR 历史；模型检查本身不提升设计评审状态。用户明确授权评审未评审设计时，先把技术处置、实际模型证据与未执行运行时验证分别记录，再更新该项状态。

后端规范与相关技术文档默认使用中文。代码标识符、命令、API 名称、哈希与原始日志保留原文；逐字捕获文件不作翻译或空白规范化。

## 2. 命令

从仓库根目录执行：

```sh
spec/quint/core/check.sh quick
spec/quint/core/check.sh simulate
CORE_VERIFY_TIMEOUT=900 spec/quint/core/check.sh verify
```

`quick` 类型检查核心入口并运行确定性测试。`simulate` 还抽样代表组合。`verify` 调用正式 bounded backend，`all` 包含三者。执行器输出本地证据目录；检查失败、请求 witness 缺失/为零、超时或源哈希变化均返回非零。`CORE_LOG_DIR` 指定本地证据目录；默认使用 `/tmp`。`CORE_VERIFY_TIMEOUT` 是预算，`CORE_SERVER_PORT` 为专用端口。

## 3. 契约与前提

- 核心假设原子持久权威、认证/有效/幂等命令、兼容且真实的提供者观测、可移植值。它检查这些接口的架构使用，不验证实现内部。
- 故障或控制可以介入时，保留 evaluation/commit、admission/entry、completion/recording、result/consumption 的独立转换。
- unknown 是权威知识。后来的失败或 not_executed 不清除较早未决工作；局部失败即使 knowledge 变为 `Recorded`，仍可逻辑未决。
- 正常逻辑失败选择检查全部保留观测与其他 admitted/未决工作，不依赖 Attempt 顺序。本地完成未记录不是权威知识。未执行证明只解除自己的 Attempt，可能使另一个保留逻辑失败变为充分；终局选择前有效成功仍充分。已有终局结果与唯一回复不被后续观测覆盖。
- 同一 Attempt 已有有效确定原观测后，迟到监视器失联报告不得因 observation_id 不同而覆盖它、重开已解除未知或追加通知。保留来源和旧 unknown 历史；局部失败仍未决；另一新 Attempt 保留自己的不确定性。见[监视器优先规则](../../../spec/architecture/authority-and-recovery.md#monitor-evidence-order)。
- 用授权事实和观测含义区分 `Executing`/`Uncertain` 与主体资格。实际签名为 `core.unresolved(at: Attempt, e: Effect): bool` 和 `core.reduce(e: Effect, at: Attempt, other: Attempt): Effect`。属性独立检查前态事实，不把这些 helper 当证明。
- 使用小记录/变量，每个 backend 入口只包含一个具体实例。Quint0.32.0 可能保留同一解析文件中未选实例的结构元数据，即使 `--main` 只选一个模块，也可能触发序列化膨胀。
- 每次结果记录工具版本、命令、域、init/step/property、源依赖哈希、depth、seed、sample count、预算、退出和耗时。来源归属必须绑定实际执行，文档新身份不代表新证据。

## 4. 结果解释

| 证据 | 允许的结论 |
| --- | --- |
| typecheck/test 通过 | 类型/语法或那些显式路径断言通过 |
| witness 到达 | 记录配置下目标可达 |
| 抽样无违例 | N条、给定 depth/seed 中未找到反例，不是证明 |
| BMC 完成 | 在该模型域与完成界限内无违例 |
| 超时/序列化/后端失败 | 无结论，不能声称请求界限完成 |
| 正检查 StateK | 仅进度，不是 depthK 完成证明 |

模型依赖改变后旧验证不适用于新源，即使入口文件哈希不变。保留历史原哈希。条件调度必须列明前提；恢复 witness 不证明必然进度。固定调度的严格递减 rank / bounded check 只覆盖指定调度和界限，不建立任意状态恢复或一般活性。

## 5. 场景

正例：原主体授权跨暂停保留，晚结果仍可记录，新授权继续受暂停封闭。

基础路径：`evaluate -> commit -> admit -> enter -> complete -> record -> consume` 经过真实 guarded 转换。

反例：属性信任动作写入的 `valid` 字段，或恢复 not_executed 清除了另一 Attempt 的未知。

## 6. 必需检查

断言独立于 guard，读取最小真实前态。适用时加入无授权/继承主体进入、旧提案、双终局回复、repeat 重用、跳 FIFO/部分提交及分支继承授权的检测变异。故意演示坏行为的通过测试只是缺口 probe，不能计入修复验收。

代表组合保留全部核心动作，并执行跨边界确定性竞态。有限身份/队列耗尽与稀疏消费必须报告；不用无条件 stutter 或无关权限 fallback 掩盖停滞。

证据归约修复覆盖另一 admitted Attempt 的未进入和本地完成未记录、终局前晚成功、非执行使保留失败充分，以及漏掉 admitted blocker 的检测变异。旧失败 trace 和通过的坏行为 probe 属历史缺口。当前结果与原缺陷摘要见[核心报告](../../../spec/quint/core/verification-report.md)。原始 `spec/quint/core/evidence/design-repair/independent-review/` 与 compact pack 都只在本地、Git 忽略。

监视器澄清要区分 guard/事实测试与排队报告投递。`lose(r: int, a: int)` 只接受 Admitted；在 nonexecution/局部失败后拒绝 lose，不执行 distinct-ID 载荷，也不保存其审计。真实延迟报告、验证和审计测试归属 I2/I3/S4。复用前核对实际依赖身份；新测试单独检查。技术处置/父会话归属文字另有文档身份。外部 API 固定到实际检查版本，源码段落仅支持候选性，不是采用测试。

抽样命令和 positivity validator 使用同一 witness 列表，每个请求项都必须出现且计数正。缺失/为零返回非零并向执行器传播。目标初始为 false；十项修复拒绝20个 missing/zero 注入案例，无关正计数不能替代缺失目标。

## 7. 错误与正确做法

错误：`knowledge == Recorded` 说明未知已解决。

正确：证据含义与授权事实不同于阶段标签。`core.unresolved(attempt, effect)` 包括 admitted、unknown 及无充分声明的局部失败；独立断言读取对应前态事实。

错误：替代主体尚未报告 LostContact，便让原主体晚失败选 Error。

正确：

```text
admit replacement -> record original logical failure -> NoResult / Executing
complete replacement successfully (local only)       -> NoResult / Executing
record replacement success                           -> one Ok / Reply
```

错误：从大模型删除接口/属性后声称等价完整覆盖。

正确：显式定义较小抽象、说明前提，并把结论限定到该抽象。

## 8. 本地证据与提交边界

**全部验证证据只保留在本地，不纳入 Git**，包括 raw capture、元数据、日志、哈希记录、原始 model/probe/ITF 副本和已经创建的 compact pack。使用根目录规则 `/spec/quint/evidence/` 与 `/spec/quint/core/evidence/`，不保留 `retained/` 例外。模型、测试、脚本与 evidence 外的人工报告/README/coverage 仍可提交。

保留证据是为了审计与复现，不等于提交证据。保留本地原始字节；用户明确授权清理索引时，先检查 HEAD/index，只按精确 evidence 路径移除索引项，保留工作文件与其他索引项，不执行宽泛 reset/add。不得把 evidence 加入检查点或提交清单。新检出依靠[中文主报告](../../../spec/quint/core/verification-report.md)中的来源绑定摘要、配置、限制与复现命令，不把未提交日志当作可独立检查的交付。

逐字副本保留来源路径、哈希、归属和可用时间；摘要标明来源与限制；原模型与 probe/test 相邻以保持 import 对应。交付文档的必需 Markdown 链接只能指向可提交报告/源码；本地 evidence 路径以代码文本标明本地专用/Git 忽略。验证原始字节、复制身份、可执行依赖哈希、零 evidence 索引项、忽略规则、JSON、可提交文件投影中的链接与人工文档空白，无需重复不变源的抽样/BMC。

Ra 仍是 ADR-007 的条件候选。Mnesia / disk_log 只是既有替代比较；本轮不增加依赖、存储后端或运行时实现。
