# Beamlet 核心 Safety 模型

状态: 首个有界可执行规格. 来源为 [RFC Q1-Q77](../rfc/0001-core-boundaries.md) 与三个 SPEC 草案.
模型收窄选择不自动成为产品决策. 尚无 Runtime/Ecto 实现代码; Mix 项目仅管理规格验证工具.

当前已暂停治理分支的继续细化, 优先 [首版范围与模型收敛提案](../spec/first-release-scope.md).
已确认首版对无法安全解决的 Unknown/冲突保持 Open、提供事实读取, 暂不提供人工裁定接口.
现有模型仍是组合参考规格, 尚未按核心/命令/治理实际隔离; 不因这里有验证场景就要求首版交付全部能力.
[依赖切割计划](dependency-cut-plan.md) 已列出实际耦合和分步验证要求, 尚未执行物理拆分.
当前先完成 [正常使用覆盖与 SPEC 一致性审查](normal-use-audit.md): 既有类型/185 场景回归通过, 执行主路径可达,
但独立回调、稳定提交身份/业务值、Handler 条件尚有覆盖缺口, 不能宣布首版模型完整. 补正常闭环优先于依赖切割.
Q78 授权区分已记入 RFC/SPEC, 尚未新增模型验证; 本次范围提案不改变 Q77 验证基线.

## 文件与模型边界

- [beamletCore.qnt](beamletCore.qnt): 主入口, 组合 `step`、扩展 step 与 Safety 性质, 再导出分层模块的公共定义. 三个双
  Worker 实例分别为禁止重复、显式接受重复风险、具备可靠资源排除协议; singleWorker 用于早期增量验证.
- [beamletCore_test.qnt](beamletCore_test.qnt): 保持原模块名的测试入口, 聚合 `scenarios/` 中的 104 个确定场景:
  strictTests 23 个、fencedTests 2 个、repeatingTests 79 个. 前缀只使用真实转换并逐步检查 safety;
  拒绝行为另检查守卫及实际 disabled action.
- [beamletCore_mutations_test.qnt](beamletCore_mutations_test.qnt): 保持原模块名与 BUG 编号的 mutation 入口, 30
  个故意错误规则位于 `mutations/`, 从合法前缀产生可定位的反例. 不属于正常 step.
- [beamletReconciliation.qnt](beamletReconciliation.qnt): Q63-Q70 的有界协调扩展,
  为核心动作提供受控的示例权限与契约输入; reconciliationStep 检查领域原语, commandStep 加入命令请求、原子处理与重投协议.
- [beamletConflicts_test.qnt](beamletConflicts_test.qnt): Q71-Q77 防御性冲突、取代与撤销测试入口, 聚合 81 个正常场景及
  14 个故意错误规则; 正常测试与 mutation 使用不同实例.
- [beamletConflicts.qnt](beamletConflicts.qnt): 冲突抽样入口, 只导入共享 fixture, 不导入测试或 mutation.
  使用明确合法前缀和 conflictSafety (即核心 commandSafety) 检查.
- [beamletRules.qnt](beamletRules.qnt): Q74-Q75 规则语义版本并存、普通退役与重投抽样入口, 导入未绑定共享 fixture; 16
  个版本场景位于 [rules_test.qnt](scenarios/repeating/rules_test.qnt), 10 个退役场景位于
  [retirement_test.qnt](scenarios/repeating/retirement_test.qnt), 汇总在 repeatingTests.
- [beamletRules_mutations_test.qnt](beamletRules_mutations_test.qnt): 五个版本错误及两个退役错误的具体入口, 错误动作位于
  [mutations/rules.qnt](mutations/rules.qnt) 与 [mutations/retirement.qnt](mutations/retirement.qnt).
- [beamletWithdrawals.qnt](beamletWithdrawals.qnt): Q76-Q77 范围撤销与命令抽样入口, 只导入共享 fixture; 22
  个撤销场景位于 [withdrawal_test.qnt](scenarios/conflicts/withdrawal_test.qnt), 12 个命令场景位于
  [withdrawal_commands_test.qnt](scenarios/conflicts/withdrawal_commands_test.qnt), 汇总在 conflictTests.
- [beamletWithdrawals_mutations_test.qnt](beamletWithdrawals_mutations_test.qnt): 九个故意错误规则入口; 实际错误动作位于
  [mutations/withdrawal.qnt](mutations/withdrawal.qnt) 与
  [mutations/withdrawal_commands.qnt](mutations/withdrawal_commands.qnt).
- [counterexamples.md](counterexamples.md): 已读取 ITF 后记录的违规前后状态与复现方式.
- [Mix task](../../tools/mix/tasks/beamlet.check.ex) 与 [Quint 检查器](../../tools/beamlet/quint_checks.ex):
  类型检查、正常场景、抽样及预期反例检查. 直接调用 Quint, 不调用 shell 脚本; 完整日志与 ITF 写入临时目录或指定目录.

### 分层目录与阅读顺序

```text
model/quint/
├── beamletCore.qnt                    # 主入口: step / safety / 具体实例
├── beamletReconciliation.qnt          # 协调与命令抽样入口
├── beamletConflicts.qnt               # 防御性冲突抽样入口
├── beamletRules.qnt                   # 规则版本抽样入口
├── beamletWithdrawals.qnt             # 范围撤销抽样入口
├── base/
│   ├── types.qnt                      # 领域类型、消息与独立观察记录
│   └── state.qnt                      # 参数、五组变量、初值、init
├── logic/                            # 纯守卫、投影与更新
│   ├── judgment.qnt / reports.qnt / dispositions.qnt
│   ├── leases.qnt / outcomes.qnt / recovery.qnt / workers.qnt
│   └── rules.qnt / reconciliation.qnt / commands.qnt
├── actions/                          # 完整赋值的协议动作, 不定义总 step
│   └── leases.qnt / workers.qnt / evidence.qnt / recovery.qnt / reconciliation.qnt
├── properties/                       # Safety 子性质与可达性见证
│   └── core.qnt / reconciliation.qnt / commands.qnt / withdrawal.qnt / witnesses.qnt
├── scenarios/
│   ├── strict/                       # fixture + 生命周期/恢复/冲突/资格测试
│   ├── fenced/                       # fixture + 可靠资源排除测试
│   ├── repeating/                    # fixture + 命令/拒绝/权限/判断版本/规则版本/协调/恢复测试
│   └── conflicts/                    # fixture + 覆盖/全部排除/取代/撤销测试
└── mutations/                        # 故意错误规则与专用合法前缀
```

建议从主入口开始, 再读 [共享状态](base/state.qnt) 与 [类型](base/types.qnt), 按问题进入对应的
`logic/`、`actions/`、`properties/`. 测试入口仍在根目录, 实际场景按实例和职责分组; 每个实例的各组通过同一个 fixture
共享状态, 不各自实例化核心. 当前 Quint 文件最多 200 行, 后续新增内容按职责拆分, 不把规则或场景重新堆回入口.

依赖方向为 **入口 → 动作/性质 → 纯逻辑 → 公共状态/类型**; 纯逻辑内部按判断投影、报告、处置、终结、协调、命令逐层组合,
无循环导入. 核心五个 `var` 与九个模型参数只在 `base/state.qnt` 声明一次. `scenarios/conflicts/fixtures.qnt`
只提供防御性输入、合法前缀与扩展 step, 不包含 `run` 或 mutant 动作.

**Quint 0.32 常量绑定约束:** 内部模块只使用未绑定的 `import ... .*` 与 `export ... .*`, 在最外层具体运行/测试/mutation
入口一次性绑定参数. 不要在 fixture 中绑定核心参数后再跨模块再导出: 这种写法可能通过 typecheck, 但执行时报
`Uninitialized const`. 新增场景组应导入现有未绑定 fixture, 由聚合模块统一导出, 而不是创建第二份状态.
分层文件用于组合与类型检查; 可执行验证仍使用下面的根目录入口命令和原 `--main` 名称. ITF
中变量的命名空间前缀可能因导入层次变化而改变, 历史反例记录仍描述其原运行.

拆分回归: `mix beamlet.check --jobs 4 --log-dir /tmp/beamlet-quint-modular-validated` 完整通过.
六个入口的类型检查覆盖全部 53 个 Quint 文件; 125 个正常场景的名称与拆分前一致, 44 个 mutation 均生成预期 ITF,
每份轨迹仍恰好包含五个状态变量. 20 组原有普通/定向运行共 32,000 条抽样轨迹, 最多 100 步, seed 42,
未发现所检查的不变量违规. 检查包含既有定向 init 及 reconciliationStep / commandStep / conflictStep; mutation 使用
mutantInit / mutantStep. 另核对 604 个原定义正文未改动 (忽略空白、注释与导入), 导入图无环且正常模拟不依赖测试/mutation
文件. `mix test` 的五个工具测试通过. 这是结构重构回归, 不新增协议语义或穷尽证明.

一个 Intent, 一个逻辑 Authority, 两个 Worker, 最多两个 Execution. 整数时钟取 0..6, TTL=2; incarnation 最多 2, 每个
Execution 的 generation 最多 3, query Report ID 与独立的协调 Command ID 域各为 1..4. 达到边界后禁用相应新动作,
不复用身份. Worker 的 Pending/完成报告分别使用同来源作用域内 ID 1/2, 不代表产品已经采用这种身份结构.

账本与审计列表仍可随重复消息不断增长, 因此这是参与者/身份域有界、轨迹长度受限的抽样模型, 不是有限状态空间穷尽检查.

## 状态与故障前提

| 状态组 | 模型内容 | 知识边界 |
| --- | --- | --- |
| authority | online 与持久 Ledger: Intent/current、尝试、lease、grant、reports、outcomes、history | Coordinator 停止不清除已提交账本 |
| workers | 存活、incarnation、收到的 lease/grant、已调用集合、易失报告和回执 | 崩溃丢失局部状态, 重启增加 incarnation |
| network | 无序 Set[Message] | 可任意延迟、丢失、乱序和重复交付 |
| external | 调用见证、效果、ResourceResult、排除旧执行事实, 以及独立协议观察见证 | 外部完成不直接修改账本 Knowledge 或 Outcome; 观察见证不是外部资源业务状态 |
| clock | Authority 整数墙钟 | 可以前跳/后跳, 相等到期 |

遵守 Q60: 非 Byzantine Worker; 合规 Worker 在已持久化许可后调用, 一次许可不允许主动重入; 已提交事务不回滚. 没有 eventual
delivery、公平调度或人工最终响应假设. 原子 SQL 是抽象前提, 不是对具体数据库锁、隔离级别、WAL、fsync 或掉电恢复的验证.

plain Quint 的选择来自 Q59: 以一个原子 Authority 为中心审查少量 Worker 消息窗口, 省去本轮不需要的 Choreo 编排结构.
五组状态独立, 外部事实与 Authority 知识使用不同类型.

重复消息通过保留可重复接收的 Report、重新发送已存 grant、丢失与重投动作表示. Set 不表示同时在途的相同字节消息数量;
不分析次数上限、拥塞或精确消息计数.

## 正常协议与性质

正常路径是建立 Prepared → 领取 → 请求/持久化授权 → 收到许可 → 调用外部 → 完成/生成报告 → 权威验证保存.
外部执行与完成各是独立动作, 可以在 Authority 离线或终结后发生.

到期会持久失效该代; 已授权且未登记可靠结果/等待的尝试变 Unknown, Waiting 保持 Waiting.
旧许可可以在到期或取消后继续引起外部调用. 临时 lease 验证与结果资格分开. 重新领取只针对从未授权 Prepared, 分配新
generation; 替代尝试原子切换 current.

普通当前 Success 的报告接收将证据、Resolved、Outcome、Closed 与 history 共同提交. Failure 先保存事实, finishFailure
是独立的“策略决定不再尝试”命令. 取消无需 Execution. 终结竞争只按合格原子提交顺序, 已终结后报告仍可保存/确认.

| 性质 | 检查内容 |
| --- | --- |
| outcomeUnique / closedIffOutcome / outcomeImmutable | Outcome 与独立提交历史至多一次; Closed iff 存在 Outcome; 首次结果不改写 |
| startupsQualified / oneStartPerExecution / grantsPersist | 授权时 Open、current、lease 有效; 一次 Execution 不再授予另一启动许可; 许可与启动历史一致 |
| invocationsAuthorized / oneCallPerExecution | 实际调用有先前持久许可并匹配调用当刻 incarnation; 同一尝试不重入 |
| expirySticky | 独立失效历史中的同一 generation 不重新有效 |
| commitsQualified / commitSnapshotsMatch | 提交当刻来源合格; 提交见证与结果一致 |
| replacementsSafe / notExecutedProofSound | 替代需要未授权、可靠未来排除证据或显式重复风险许可; 可靠排除不只是 not_found |
| knowledgeEvidenced / reportsAuthenticated | 权威 Knowledge 有已存有效报告; 已存来源与持久关联一致 |
| receiptsOnlyForStored / reportAuditAtomic / outcomeAuditAtomic | 持久化回执不先于证据; 保存证据/终结的审计数量与对应事实一致 |
| resolvedKnowledgeCoherent | 有确定知识的尝试不被迟到 Pending 回退到 Waiting |
| failureRespectsOldSuccess | 普通 Failed 提交当刻不能已有尚未协调的旧成功证据 |
| reconciliationQualified | 决定提交时 Open、主体/契约条件合格、审查版本与接受时版本相等 |
| judgmentRevisionSound | 独立变化链连续、相关变化递增版本, 当前判断投影与变化链一致 |
| reconciledEvidencePreserved / reconciliationAuditAtomic | 原始审查证据保留, 每份协调决定与协调 History 一致 |
| commandRecordsUnique / commandRecordsImmutable / rejectedCommandsImmutable | 成功与领域拒绝共用一个 ID 作用域; 原请求与原结果不改写 |
| commandExecutionMatchesRequest / commandEffectsAtomic | 实际采用的决定与提交请求一致; 命令记录、决定和 History 原子一致 |
| commandResultsOriginal / commandRepliesSound | 保存原处理结果; 成功回复不能先于相应持久记录 |
| commandHandlingSound | 按处理当刻的原成功/拒绝记录识别重投; 新请求按当前权限和资格处理 |
| rejectionQualified / rejectionEffectsAtomic | 入域后的明确拒绝原子保存身份、结果及审计, 不制造决定或 Outcome |
| commandReadAuthorized | 当前处理没有读取权限时回复不包含原结果或 Authority 判断上下文 |
| conflictCoverageSound | 接受的处置覆盖审查时完整相关报告, 每报告一项处置, 契约核验成立 |
| conflictHistoryPreserved | 原始矛盾报告仍对应历史冲突, 不通过清除标志假装未发生 |
| terminalConflictsResolved | 成功/失败提交当刻没有尚未解除的冲突阻塞; 取消独立处理 |
| excludedAllKnowledgeSound / allExcludedCommitSound | 全部明确排除后的判断保持未知; 全部排除命令不产生终结结果 |
| supersessionLinksSound / dispositionBindingsUnique / decisionsImmutable | 取代链接覆盖对应旧处置且无越界、自引用或失效目标; 每报告当前绑定唯一; 旧决定值与独立快照一致 |
| automaticRuleVersionsSound | 按接受时规则定义检查实际指定版本与条件, 不只信任 actorQualified 标志 |
| ordinaryRuleRetirementSound | 普通退役的独立观察须保持账本、当前适用绑定及判断版本; 指定版本从可信登记输入移除 |
| withdrawalScopeSound / withdrawalCommandsNonterminal | 撤销只移除指定当前绑定, 不恢复历史绑定或新增处置; 检查精确核验依据, 原结果无 Outcome |

starts、commits、firstOutcome、invalidLeases、retries 与 decisions 中的快照用于观察历史事实, 并非最终 SQL schema. 例如
invalidLeases 是独立历史见证, leaseValid 不使用它作第二重屏障; 否则遗忘当前 invalidated 标志的错误可能被辅助变量掩盖.

这些性质检查抽象状态组合与部分协议顺序, 并检查在明确契约输入下采用/排除旧成功的协议. 不证明真实结果正文、完整 Operation
语义、条件核验的外部真实性、数据库实现或外部效果恰好一次.

## 明确收窄的模型选择

1. ALLOW_REPEAT=true 只表示此模型实例显式接受重复风险. 不模拟可靠幂等协议, 也不把“支持幂等”的声明当作真实保证. fenced
   实例把“可永久排除旧尝试未来执行且尚未发生”视为可信资源原子协议, 比一般单调 fencing token 的能力强; 它不是仅在 Beamlet
   中递增 generation.

2. Failure 表示本次外部调用结束且结果为错误, 可以已产生部分效果. Q62 已确认: 旧成功证据未协调时阻止普通 Failed.
   守卫检查已存报告, 不仅检查缓存 Knowledge; 即使所有尝试都有已知结果, 旧成功仍会阻塞普通失败. Q63/Q64
   扩展可记录对具体报告的排除决定以解除本次判断的阻塞, 也可经协调采用旧成功并原子提交结果. Q71
   增加完整相关报告处置的有界冲突解除例子; 完整产品相关性、预算与错误策略仍未编码. 显式 Cancelled 仍可接受.
   oldSuccessAtCommit 是独立提交见证, 检查提交当刻证据, 不用未来报告追溯推翻已提交结果.

3. queryExternal 代表受信来源形成证据; 不是核心直接信任第三方正文. Callback 的
   correlation、认证、早到回调与关联持久化用抽象 Execution/grant 关联代替. 已覆盖完成先于 Pending, 尚未验证具体 Callback
   Adapter 协议.

4. Q61 已确认: Report 冲突计算保留原始证据并独立设 conflict, 保留最近有依据的生命周期/知识投影.
   defensiveConflictProjectionTest 与 conflictDoesNotClearOnNewReportTest 检查 Resolved 和 Waiting
   下的矛盾、后续报告不清除冲突、既有 Outcome 不改写及显式取消仍可接受. 合规环境不会凭空产生矛盾终结报告,
   这些是纯规则的防御性场景, 不声称随机主模型覆盖恶意或损坏来源. Q71 防御性扩展额外放宽查询来源的一致性前提,
   允许已通过抽象入口核验的来源给出相互矛盾报告, 用以验证冲突处理; 不声称合规资源必然产生这种报告, 不验证 Byzantine
   Worker 或真实认证.

5. 到期确认由 expireLease 或 Prepared reclaim 显式持久化. 续租/启动到期拒绝的返回、失效事实与事务异常如何共同提交,
   仍待原子命令 SPEC 定义. 本模型不代表所有拒绝路径均已设计完成.

6. History 使用最小 kind/exec 占位, 以辅助快照检查重要理由; 未建立产品 provenance schema. 已覆盖本轮协调领域拒绝的审计;
   其余拒绝路径、完整失联检测、资源限制、调度发现、Outbox、正式 Authority Transfer 及 SQL 并发实现仍未建模.

7. Q63/Q64 决定携带具体报告、采用/排除、主体与依据码, 与 History 原子记录. Q70 将新决定的审查校验改为 reviewedRevision
   与当前 revision 相等. 已接受处置按独立 acceptedBase 判断后续适用范围, 不因处置自身递增版本而立即失效;
   新报告/资格变化使其失去直接解除阻塞的效力. 该保守模型投影包含完整报告、current、Intent phase 及尝试的
   exists/phase/grant/knowledge/conflict, 排除 lease 控制、纯拒绝审计、命令缓存与 transport; 不是产品最终变化清单或 SQL
   字段.

8. ReconciliationPolicy 是 Authority 侧受信的权限与已核验契约输入, 不由不可信命令任意传入. 示例只有主体 1 获授权; rule 1
   支持受信查询成功的采用, rule 2 支持具有明确契约排除依据的报告. 未登记规则和条件不符均禁用. excludable
   成员关系抽象外部/契约核验已经成立, 不证明真实成功可被随意排除. VerifiedCompletion / ContractExclusion 是抽象依据码,
   尚非产品 provenance schema. 实际认证、规则版本、凭据、依据正文和核验正确性均未验证.

9. Q65/Q66 的 commandStep 把提交请求与处理请求拆为两个动作, 因而可插入新证据、心跳、崩溃及终结.
   已提交命令查找先于新请求资格校验; 同 ID 同内容返回原处理结果, 同 ID 不同内容拒绝. 已终结或已有新证据不改变原结果,
   重投不重新执行决定. 自动新求值使用新命令身份. 命令内容比较为结构化领域值比较, 不验证真实 codec.

10. Q67 扩展保存成功与明确领域拒绝的身份及原结果. 模型使用 commands/rejections 两个列表观察分类, 但 ID 作用域共享,
    不批准两个去重命名空间或新 SQL 表. 过期审查和当前不可采用都保存拒绝与 History; 重新求值须用新 ID.
    权限校验失败不进入领域处理、不占用身份. 格式校验、通信/数据库异常和记录清理未建模; 成功持久性仍是原子数据库前提.
    重投候选表示调用方保留原请求, 不规定客户端持久化实现.

11. commandCommits、rejectionCommits 和 external.commandHandling 是独立观察见证: 保存原记录、实际决定关联和处理前后效果,
    检查静默改写请求、重复执行、返回最新结果或错误拒绝重投. 它们不是 SQL 字段. commandSafety 包含原 safety
    及命令协议性质; 只运行普通 step 或 reconciliationStep 不足以覆盖命令协议.

12. Q68 以 Authority 已核验的当前权限事实 CommandAccess 表达提交/读取能力, 不是客户端可自行声明的命令字段.
    处理动作可非确定选择权限, 表示请求之间权限变化. 新请求需当前提交能力及合法主体; 已处理请求读取只需当前读取能力,
    不再要求提交能力. 无读取能力时只返回 CommandForbidden 请求标识, 保留原记录. 已允许的提交可以持久处理而隐去结果,
    后续有读取能力时再取原结果. 这不指定 HTTP 状态码. 未验证真实身份绑定、ACL 存储、权限校验协议或消息接收端;
    读取检查发生在形成新回复时.

13. rejectedStaleInit 是真实合法前缀, 含一次已经提交的过期审查拒绝. 原拒绝中的报告上下文属于当时, 不是当前报告集合;
    新报告、条件改善、重启或权限变化不改写原拒绝. 新增见证覆盖拒绝保存、只读重投与读取拒绝;
    初始化即成立的拒绝见证不算该前缀的新保存覆盖.

14. Q69 确认命令身份与原结果随保留的 Intent 持续保留, 不默认 TTL 清理. 当前模型不删除 Intent 或命令记录,
    与该保留原则一致; 归档、清理及删除后的身份语义仍未建模. 本轮仅记录该决议, 不新增清理动作或 SQL 实现.

15. Q70 的 judgmentChanges 是独立变化见证, 与判断版本增长一同记录, 不作为执行守卫. judgmentRevisionSound 从
    initialLedger 折叠连续变化链, 对照当前判断投影和版本, 检出漏增、误增及重置. 同一原子操作可包含多个相关转换,
    版本允许增长多次; 不规定每个事务恰好 +1. stale 回复保留处理时版本与判断投影, 包含协调变化, 不是只返回报告列表;
    模型投影并非批准具体回复字段或编码. 权限/外部条件仍按处理当刻重验, 不依靠判断版本锁定外部世界. 版本回绕、SQL
    compare-and-swap、真实相关变化全集及归档/迁移协议尚未验证.

16. Q71 的 Decision.evidence 逐份记录报告、KeepEvidence/ExcludeEvidence 和依据码.
    本模型保守地要求覆盖每个历史冲突尝试的全部已存报告, 加上主结果报告; 这是相关性范围的模型收窄,
    不是产品要求所有无关材料一律参与. 不允许同报告双重处置或同时保留相互矛盾结果. Q72
    移除每个尝试必须保留确定证据的模型限制, 允许全部排除后判断仍未知, 并保留已授权未知风险. resolutions 是 Authority
    已核验的整组逐项契约事实; 即使它包含一个遗漏报告的集合, 覆盖守卫仍独立拒绝. 它不证明任何真实成功都可被排除.

17. 历史 conflict 标志、原始 reports 和最近有依据的 Knowledge 不改写. noConflicts 判断当前是否仍受阻塞,
    judgmentKnowledge/hasEvidence 按适用处置解释本次判断. 新报告或资格变化使旧处置失去直接适用性; 重投只返回原处理结果.
    AdoptFailure 还要求当前结果来源、没有未解释旧成功与没有已授权未知尝试, 不借冲突协调绕过失败守卫.
    成功/失败均检查处置后的终结资格, 与决定、命令及审计原子提交. Q73 以显式 supersedes 引用更新逐报告绑定,
    只移除引用目标及对应报告的旧适用关系; 原命令结果与历史保持不变. 未完全被取代的旧决定继续支持其剩余范围,
    不把整份决定隐式撤销. 精确冲突分组、完整依据正文及真实核验协议仍待设计.

18. Q73 的 decisionIndex 使用不可删除列表的位置抽象 Intent 内稳定决定身份, 不等于 Command ID, 不批准 SQL 主键或公开 ID
    编码. 为收窄路径, 本模型重新处置已判断报告一律要求引用其历史链上的当前绑定, 包括同一处理的重新确认;
    产品的最小引用要求尚未细化. 新证据导致适用性失效, 不删除历史关系; 构造新提案时可生成明确引用,
    接收处理绝不自动补齐或重定向请求. 原始主报告形式的旧决定也进入取代校验, 但其原有 Knowledge 语义保留.

19. historicalBindings 按已保存的显式边折叠; applicableBindings 再按接受时证据/资格范围判断当前适用性. 这些是抽象投影,
    不规定通过事件重放恢复产品状态. supersessionLinksSound 对接受前缀逐项检查目标和覆盖, 不只依靠 admission bool;
    decisionSnapshots 是独立不可变性见证, 不作执行守卫, 不是新 SQL 表/字段. 同一个原子提交保存决定及其引用,
    命令与决定内容比较也包含引用. Q76 扩展范围撤销的抽象判断语义; 完整撤销协议、决定删除、跨 Intent 引用与 SQL
    并发实现仍未建模.

20. Q74 的 RuleReference={id,version} 用整数抽象具体语义版本, 不批准公开 codec、semver 或 SQL 字段. RuleRegistration 是
    Authority 已核验的版本与条件输入; 示例 rule2 的 v1 允许 Worker 成功报告按契约排除, v2 额外要求查询来源.
    多版本可并存, 精确匹配须唯一; 同一引用出现相互矛盾的定义则不能接受新决定. rulesAtDecision 保存接受时的抽象定义见证,
    性质不使用处理时当前登记去重解释历史. 此快照不是获批的全注册表持久化方案, 不验证规则源码或真实条件核验.

21. 有界规则扩展按处理动作选择并存或仅 v2 的可信策略, 不增加第六个状态变量或模拟真实注册表部署.
    新命令的规则身份用于入域资格, 指定版本的登记/条件属于领域核验; 已允许身份但未知版本形成持久 DecisionIneligible.
    这是抽象入口收窄, 不批准产品权限映射、缺失字段/格式错误分类或版本零的编码语义.
    已处理命令优先查找并按读取权限返回原结果, 不再要求旧版本在当前登记中存在. 自动重算显式选择版本和新身份,
    不在接收端重写请求.

22. 规则定义稳定性、登记事务/撤权、代码与语义版本映射及历史解释材料保留未验证. Q75 确认普通退役只阻止新提交,
    不自动撤销已接受处置, 不单独改变当前判断或判断版本. 旧处置仍受 acceptedBase 证据/资格范围与显式取代关系约束.
    撤销既有处置须明确、可审计地改变当前判断并推进判断版本, 具体命令与协议待设计; 旧决定、原命令结果和已有 Outcome 保留.

23. retireRuleVersion 表示普通退役的可信策略输入边界, 只增加 external.ruleRetirements 独立观察, 不修改 Intent 账本,
    不模拟真实注册表存储或部署事务. retiredRulePolicy 精确移除指定身份/版本, 保留其他版本; 后续动作显式接收移除后的策略.
    三组 retirementStep 定向运行都不再选择含 v1 的策略, 与 Q74 可来回选择策略的版本兼容性运行分开.
    观察记录包含前后适用绑定、判断版本与整个账本相等性, 不用作执行守卫. 两条故意错误规则即使伪造 durableUnchanged=true,
    也分别因实际绑定丢失/版本误增被检出. 观察不会要求后来新证据或显式取代后仍保持同一绑定.

24. 当前普通退役抽象不在每个 Intent 追加 History; 本轮不规定注册表操作的全局审计存储. Q75 检查点尚未建模显式撤销; Q76
    已增加判断语义的抽象例子, Q77 确认撤销复用命令身份/原结果重投及首次接受原子保存语义.
    具体权限、理由、范围表示、事务实现和重复提交接口仍未实现, 不把普通退役动作作为撤销接口.

25. Q76 用 WithdrawDisposition 与 VerifiedWithdrawal 抽象范围撤销, 复用 Decision.supersedes
    明确引用当前所有者及报告范围. decisionTreatments 对撤销返回空集, advanceBindings 只删除引用绑定,
    不加入任何新采用/排除关系; 被更早取代的关系仍然不会恢复. 判断版本随新的审计决定递增. 撤销不解决冲突,
    所以不要求本次撤销覆盖全部冲突报告; 部分范围撤销后必要阻塞由原报告和剩余绑定重算. 新的采用/排除仍按 Q71
    完整性要求审查.

26. ReconciliationPolicy.withdrawals 是 Authority 已核验的精确撤销范围/依据集合, 不是命令自报的授权,
    不证明真实规则缺陷或核验过程. 模型保守地只撤销当前仍适用的非空绑定, Open 才接受新撤销,
    主报告须位于撤销范围且来自已存合法证据. Closed 新请求拒绝, 已处理请求仍按当前读取权限返回原结果; 不批准产品在 Closed
    上追加历史撤销的最小规则. 原始报告、旧决定、命令与结果不变.

27. Q77 已确认撤销复用协调 Command ID、审查 revision、原结果重投和审计/拒绝规则, 共用同一 Intent 身份域.
    模型沿用同一处理动作与已核验输入, 不批准具体撤销 API、专属权限或 SQL schema; 独立操作种类在模型 Decision 中编码,
    不是要求产品沿用该类型表示.
    bindingsBefore 与 withdrawalsAtDecision 保存独立观察快照, 用于 properties/withdrawal.qnt
    核对接受时当前目标和作用范围, 不作执行守卫. 性质对撤销前缀的实际绑定检查“原绑定减明确范围”, 并核对指定依据; 不只依赖
    contractQualified/supersessionQualified 布尔见证. 撤销本身无 Outcome, 也不修改重试策略/Start Authorization.
    撤销之后的新合法决定仍可建立新的绑定, 不将撤销解释为永久禁用这份报告.

## 部分范围取代的模型例子

partiallySupersededInit 通过真实协议先保存 D0 的三报告全部排除, 再保存 D1 的两报告重处置. 旧决定完整保留;
当前绑定只在明确引用的范围内改变:

| 报告 | D0 后 | D1 后 | D2 再次全部排除后 |
| --- | --- | --- | --- |
| success1 | D0 / 排除 | D1 / 排除 | D2 / 排除 |
| disputedFailure | D0 / 排除 | D1 / 采用 | D2 / 排除 |
| failure2 | D0 / 排除 | D0 / 排除 | D2 / 排除 |

D1 引用 D0 的 success1 与 disputedFailure, 不取代 failure2. D2 对三报告重新判断时分别引用 D0 的 failure2 与 D1
的另外两报告. 同报告不能只引用更早的 D0 来绕过它已经被 D1 取代的范围. 这些 D 标签只说明模型中的稳定决定位置, 不指定产品
ID.

## 撤销不会恢复旧处置的模型例子

withdrawalPendingInit 从 partiallySupersededInit 继续: D0 对三报告全部排除, D1 明确取代其中两份的处置. W 撤销 D1
的两份当前处置, 但不删除历史链接或恢复 D0 的两份旧排除:

| 报告 | D1 后 | W 后 | 新合格决定 D3 后 |
| --- | --- | --- | --- |
| success1 | D1 / 排除 | 无当前处置 | D3 / 排除 |
| disputedFailure | D1 / 采用 | 无当前处置 | D3 / 排除 |
| failure2 | D0 / 排除 | D0 / 排除 | D3 / 排除 |

W 后原冲突和旧成功重新阻塞普通终结, Intent 保持 Open, 原 reports/Knowledge/History 与各命令原结果保留. D3
是重新审查后以新身份提出的合格决定, 对仍有效的 failure2 引用 D0, 对已撤销且无当前所有者的两份报告不恢复任何旧边. D3
本次全部排除仍保持结果未知, 不生成 Outcome. 此图是抽象当前关系, 不规定产品通过历史重放恢复.

## 执行与复现

工具: Quint 0.32.0, 默认 Rust 后端. 不使用 quint verify / Apalache. 确定场景以 max-samples=1 执行; 增量构建从
singleWorker 创建路径开始, 每次新增正常动作均运行 typecheck 与短 quint run. 单元纯守卫也已通过 TypeScript REPL 用手工
Ledger 检查创建阻塞与 NotFound 不产生 Knowledge.

从仓库根目录运行:

```console
mix beamlet.check
mix beamlet.check --phase test
mix beamlet.check --samples 5000 --directed-samples 1000 --jobs 4 --threads 4 --log-dir /tmp/beamlet-quint
mix test
```

默认三个核心实例各 5,000 条、最多 100 步; 五组核心合法前缀各 1,000 条, 协调原语扩展的普通 init 与合法前缀各 1,000 条;
命令协议的普通 init 与三个合法前缀各 1,000 条, 防御性冲突扩展六个合法前缀各 1,000 条 (含 allExcludedInit 与
partiallySupersededInit), 规则版本扩展三个合法前缀、普通退役扩展三个合法前缀及范围撤销扩展四个合法前缀各 1,000 条,
均最多 100 步. 默认合计 42,000 条轨迹. 使用 --samples、--directed-samples 调整预算, --jobs 控制独立进程并发, --threads
控制每个 Rust 模拟进程的线程上限, --log-dir 指定日志目录. 未指定 --threads 时取 max(div(System.schedulers_online(),
jobs), 1), 例如 16 个在线 scheduler、jobs=4 时默认每进程 4 线程; 这是保守预算, 不是最优性能保证,
也不保证准确反映所有容器 CPU 配额. typecheck 与 test 不接收线程参数; 单样本 mutation 反例固定使用 1 个模拟线程. --phase
支持 all、typecheck、test、simulate、mutations. Mix 仅接受退出 1 且报告 Invariant violated 并产生非空 ITF 的预期
mutation 结果, 不将类型错误或运行错误视为检出. 重用目录时先删除该次 mutation 的旧 ITF, 防止陈旧文件满足检查. mix test
检查工具拒绝误报的行为; 不代替 Quint 场景与抽样.

每次运行在日志目录写入 `run-info.txt` (Quint 版本、Rust 后端、在线 scheduler 数、jobs/threads、抽样预算、seed 与阶段) 和
`timings.tsv` (任务、阶段与运行的 passed/failed 及毫秒墙钟耗时). 重用目录时这两份报告重新生成, 不累计旧计时.
并发任务的耗时不能相加作为总耗时; 阶段/运行耗时包含调度和任务处理, 运行计时不含最初的版本查询和报告初始化.
更改线程配置后保留完整配置和输出, 不只凭同一个 seed 假定轨迹完全相同.

冲突扩展也可单独运行 (默认 init 执行合法冲突前缀):

```sh
quint run model/quint/beamletConflicts.qnt --invariant safety \
  --max-samples 1000 --max-steps 100 --seed 42
```

分别复现:

```sh
quint typecheck model/quint/beamletCore.qnt
quint typecheck model/quint/beamletCore_test.qnt
quint typecheck model/quint/beamletCore_mutations_test.qnt
quint typecheck model/quint/beamletReconciliation.qnt
quint run model/quint/beamletReconciliation.qnt --main beamletReconciliation \
  --step reconciliationStep --invariant safety \
  --max-samples 1000 --max-steps 100 --seed 42 --backend rust --verbosity 1
quint run model/quint/beamletCore_test.qnt --main repeatingTests --init committedExclusionInit \
  --step commandStep --invariant commandSafety \
  --witnesses commandCommittedReached commandReplayReached staleCommandRejectedReached commandIdentityConflictReached \
  --max-samples 1000 --max-steps 100 --seed 42 --backend rust --verbosity 1
quint test model/quint/beamletCore_test.qnt --main strictTests --seed 42 --max-samples 1
quint test model/quint/beamletCore_test.qnt --main fencedTests --seed 42 --max-samples 1
quint test model/quint/beamletCore_test.qnt --main repeatingTests --seed 42 --max-samples 1
quint run model/quint/beamletCore.qnt --main beamletCoreAnalysis --invariant safety \
  --max-samples 5000 --max-steps 100 --seed 42 --backend rust --verbosity 1
quint run model/quint/beamletCore_test.qnt --main strictTests --init grantedInit \
  --invariant safety --witnesses succeededReached failedReached externalCallReached \
  --max-samples 1000 --max-steps 100 --seed 42 --backend rust --verbosity 1
```

preparedInit/grantedInit/grantHeldInit/replacementInit/oldSuccessCurrentFailureInit/committedExclusionInit/rejectedStaleInit
都执行真实守卫从 init 到达, 不是任意重置状态. 定向初始化偏置覆盖, 不能代替从普通 init 的检查. 从正常 init
很多随机轨迹先取消或崩溃, 深路径稀少; 单看 No violation found 会夸大信心.

## 运行记录与覆盖

Q59/Q60 首轮记录: 正常场景 26/26 通过, 9/9 mutation 检出指定违规. Q61/Q62
新增旧成功与当前失败的两种报告顺序、显式取消、两个确定失败的正向场景, 并补充冲突不随新报告清除的纯规则测试;
增加忽略旧成功的 mutation. [反例记录](counterexamples.md) 对应已读取的 ITF. 检出指定规则错误不代表全面 mutation 覆盖.

Q59/Q60 检查点: 禁止重复/接受重复风险/资源排除三个普通实例各 5,000 条、最多 100 步, 输入 seed 42. 授权见证分别 46/46/30
条, 普通 init 的深路径覆盖较低. 将 ResourceResult 与权威 Knowledge 分成独立类型后完整复跑, 连同四组合法前缀共 19,000
条抽样轨迹, 未发现所列 Safety 违规. 当时的 26 个正常场景与 9 个 mutation 检测场景全部通过, 9
条故意错误规则均产生预期反例. 日志保存在 /tmp/beamlet-quint-final.

Q61/Q62 检查点: 已通过当时的检查入口完整复跑, 31/31 正常场景与 10/10 mutation 检测场景通过, 10
条故意错误规则均实际报告预期违规. 三个普通实例各 5,000 条、五组合法前缀各 1,000 条, 共 20,000 条抽样轨迹, 每条最多 100
步, 输入 seed 42; 未发现所列 Safety 违规. 新增 oldSuccessCurrentFailureInit 使用真实协议动作保存两种结果并保持 Open,
用于检查旧成功阻塞状态下的后续竞争. 完整日志与 ITF 保存在 /tmp/beamlet-quint-q61-q62, 可用 runner 重新生成.

Q63/Q64 协调扩展: 45/45 正常场景与 14/14 mutation 检测场景通过, 14 条故意错误规则均产生指定违规; 最新 ITF 已全部读取,
新增 4 条已核对违规转换前后的决定/证据/结果. 三个核心实例各 5,000 条、五组核心合法前缀各 1,000 条、协调扩展普通 init
与合法前缀各 1,000 条, 共 22,000 条抽样轨迹, 每条最多 100 步, 输入 seed 42, 未发现所列 Safety 违规.
增加人工采用/排除、自动规则条件、无规则时人工处理、未授权/未登记/条件不符拒绝、过期快照拒绝、新证据重新阻塞和取消竞争场景.
日志保存在 /tmp/beamlet-quint-q63-q64.

协调定向前缀的 1,000 条轨迹中, 人工决定、自动决定、排除决定、采用决定分别命中 853 / 356 / 459 / 802 条轨迹.
这些是命中轨迹数, 不代表完整覆盖或统计证明. 权限和外部契约条件仍是已核验输入的抽象前提.

Q65/Q66 命令协议扩展: runner 完整复跑, 59/59 正常场景及 20/20 mutation 检测场景通过, 20 条故意错误规则实际产生指定违规.
最新 ITF 已全部读取, 新增六条核对了原请求、实际决定、持久记录和回复的违规前后状态. 三个核心实例各 5,000 条,
五组核心前缀、两组协调原语运行与三组命令协议运行各 1,000 条, 共 25,000 条抽样轨迹; 均最多 100 步, 输入 seed 42,
未发现所列 commandSafety 违规. 日志与反例保存在 /tmp/beamlet-quint-q65-q66.

命令协议的 oldSuccessCurrentFailureInit 前缀中尚无命令记录; 1,000 条轨迹里,
首次提交、重投回复、过期请求拒绝、身份冲突分别命中 417 / 357 / 877 / 404 条. committedExclusionInit 已包含一次合法提交,
其 1,000 条轨迹里重投、过期请求拒绝、身份冲突分别命中 947 / 838 / 988 条; 初始化即成立的 commandCommittedReached
不算这组前缀的新提交覆盖. 确定场景另外覆盖同 ID 两种竞争提交顺序、心跳、重启、Closed 下重投与自动新求值.

Q67/Q68 最终检查点: runner 完整复跑, 70/70 正常场景和 26/26 mutation 检测场景通过. 26 条故意错误规则均产生指定违规; ITF
全部读取, 新增六条逐一核对了违规前后的原身份/结果、读取/提交权限与实际回复. 三个核心实例各 5,000 条,
五组核心前缀、两组协调原语运行及四组命令协议运行各 1,000 条, 共 26,000 条抽样轨迹, 每条最多 100 步, 输入 seed 42;
未发现所列 commandSafety 违规. 日志与反例保存在 /tmp/beamlet-quint-q67-q68-final.

确定场景覆盖拒绝原子保存、拒绝响应丢失/重启、旧拒绝重投、新 ID
重新判断、权限失败不占用身份、提交/读取权限独立及权限恢复后的原结果读取. 以下均为 1,000 条轨迹的命中数;
“—”表示目标在初始化已成立, 不用它证明后续新保存:

| 命令协议合法前缀 | 首次成功保存 | 拒绝保存 | 只读原结果重投 | 读取拒绝 |
| --- | ---: | ---: | ---: | ---: |
| oldSuccessCurrentFailureInit | 213 | 994 | 544 | 1000 |
| committedExclusionInit | — | 964 | 652 | 999 |
| rejectedStaleInit | 182 | — | 683 | 999 |

保存结果的 witness 表示运行中目标曾达到, 不是事件次数或统计证明. rejectedStaleInit 初始也已经达到
staleCommandRejectedReached, 其 1000 命中不算新的过期拒绝覆盖.

本轮权限见证只统计当前可读、当前不可提交且原请求与已处理记录完全相同的重投, 不把同 ID 不同内容的身份冲突计为读取原结果.
初始化已包含成功或拒绝记录的前缀, 相应保存见证初始即成立, 不用它证明后续新保存.

Q70 判断版本检查点: runner 完整复跑, 78/78 正常场景 (strictTests 23、fencedTests 2、repeatingTests 53) 与 30/30 mutation
检测场景通过. 30 条故意错误规则均产生指定违规, 全部 ITF 已读取;
新增四条逐一核对了当前版本、独立变化链、报告及决定的违规前后状态. 相关处置/新证据漏增版本、普通心跳误增和版本重置均被
judgmentRevisionSound 检出. 原有过期请求、静默刷新、原结果重投及权限错误仍能检出.

14 组正常运行共 26,000 条抽样轨迹, 每条最多 100 步, 输入 seed 42, Quint 0.32.0 / Rust; 未发现各运行所检查的
commandSafety 违规. 日志与 ITF 保存在 /tmp/beamlet-quint-q70.
新增确定场景覆盖无新报告的并发协调失效、新版审查提交、纯拒绝审计不使其他审查失效、处置自身递增后仍可正常失败终结、重投/读取拒绝/心跳/重复报告/重启不改变版本,
以及创建、授权、Unknown、替代和关闭的相关变化.

Q70 命令协议前缀的首次成功保存 / 拒绝保存 / 只读原结果重投 / 读取拒绝见证: oldSuccessCurrentFailureInit 为 212 / 989 /
521 / 999; committedExclusionInit 为 初始成立 / 970 / 669 / 1000; rejectedStaleInit 为 157 / 初始成立 / 671 / 999.
计数均为 1,000 条轨迹中的命中数, 可重叠, 不代表事件次数、完整覆盖或统计证明; 初始化已成立的目标不用于证明新的保存.

Q71 冲突协调检查点: 按当时的检查集完成验证, 101/101 正常场景 (23 + 2 + 53 + 23) 及 37/37 mutation 检测场景通过.
最新冲突场景在完整性反例细化后再次全部通过. 全部 37 份 ITF 已读取;
新增七条逐一核对了覆盖/依据、原报告、历史冲突、提交时阻塞及持久命令的违规前后状态. 覆盖不足但逐项依据合格的反例
(coverageQualified=false, evidenceQualified=true) 与覆盖完整但缺少依据的反例分别检出, 不用一个守卫替代另一个.

18 组正常运行共 30,000 条抽样轨迹, 每条最多 100 步, 输入 seed 42, Quint 0.32.0 / Rust; 未发现所检查的 commandSafety /
conflictSafety 违规 (后者为前者的绑定别名). 包含前 14 组核心/协调/命令运行和新增四组防御性冲突前缀. 日志与 ITF 保存在
/tmp/beamlet-quint-q71-final. 冲突入口放宽来源一致性、整组契约核验为受信前提, 不证明真实来源、契约、SQL
或外部结果的真实性.

以下每组均为 1,000 条轨迹的命中数, 可以重叠; “—”表示处置目标在初始化已成立, 不用于证明新的处置提交:

| 防御性冲突前缀 | 明确处置 | 成功终结 | 失败终结 |
| --- | ---: | ---: | ---: |
| conflictInit | 192 | 15 | 91 |
| queriedConflictInit | 163 | 163 | 0 |
| bothConflictsInit | 169 | 169 | 0 |
| resolvedConflictInit | — | 15 | 244 |

queriedConflictInit 与 bothConflictsInit 的新成功证据上下文未提供相应失败处置所需的完整排除依据,
不用零失败命中声称覆盖失败路径. 合格失败由 conflictInit / resolvedConflictInit 及确定场景覆盖.
计数不是事件次数、完整覆盖或统计证明. 命令重投、取消、Unknown
不可被冲突协调绕过、同身份不同内容、逐项依据与原证据保留均有确定场景检查.

Q72 与 Mix 迁移检查点: 通过 mix beamlet.check 完整检查. 六个模型文件类型检查通过, 113/113 正常场景 (23 + 2 + 53 + 35) 与
39/39 mutation 检测场景通过. 全部 39 份 ITF 已读取; 两个新增反例逐一核对了未改变的原报告、处置、命令原结果和错误终结.
excludedAllUsesCachedKnowledge 在 24 步合法前缀后错误提交 Failed, 提交见证 sourceEligible=false;
excludedAllCreatesOutcome 在 23 步合法前缀后把全部排除命令与 Succeeded 一同保存, 被 allExcludedCommitSound 检出.

19 组正常运行共 31,000 条抽样轨迹, 每条最多 100 步, 输入 seed 42, Quint 0.32.0 / Rust; 未发现所检查的 commandSafety /
conflictSafety 违规. 日志与反例保存在 /tmp/beamlet-quint-q72-final, 汇总日志 /tmp/beamlet-quint-q72-final.log. mix test
的五个工具测试通过, 覆盖解析/运行错误、错误退出码、缺失/空反例文件和非法 CLI 参数的拒绝; 格式、编译与主动诊断检查通过.
不将工具测试计入 Quint 场景数.

新增 12
个正常场景检查全部排除仍未知、原报告/历史保留、原结果重投、新证据重新阻塞及新版采用、缺少依据拒绝、登记自动规则、两组冲突全部排除、取消、混入保留项拒绝、未知风险阻止明确失败采用,
以及新旧处置连续变化不回退使用旧记录. 执行历史的 phase / Knowledge 缓存保留, 当前 judgmentKnowledge 单独保持未知;
不把全部排除伪装为未执行或新增重试许可.

以下各组为 1,000 条轨迹的见证命中数, 可重叠; “—”表示初始化已成立, 不能当作新的处置覆盖:

| 防御性冲突前缀 | 明确处置 | 全部排除处置 | 成功终结 | 失败终结 |
| --- | ---: | ---: | ---: | ---: |
| conflictInit | 147 | 65 | 19 | 37 |
| queriedConflictInit | 76 | 0 | 76 | 0 |
| bothConflictsInit | 141 | 68 | 75 | 0 |
| resolvedConflictInit | — | 73 | 10 | 182 |
| allExcludedInit | — | — | 7 | 25 |

allExcludedInit 后续合格终结来自新的明确核验与决定或后续证据, 不归因于原全部排除命令; 确定场景独立检查两者.
queriedConflictInit 未提供覆盖新增成功报告的全部排除契约集合, 不把零命中当作该路径的覆盖. 这些均为抽样观察,
不是穷尽证明、Liveness、真实契约核验或 SQL 并发验证.

Q73 显式取代检查点: mix beamlet.check 完整通过六文件类型检查, 125/125 正常场景 (23 + 2 + 53 + 47) 及 44/44 mutation
检测场景. 全部 44 份 ITF 已读取, 新增五份逐一核对了原报告、接受前缀、实际链接、当前绑定与独立旧决定快照.
前三条故意错误规则把 supersessionQualified 伪造为 true, 仍由实际目标/范围检查检出.

| 新反例 | 合法前缀步数 | 核对的违规 |
| --- | ---: | --- |
| implicitSupersession | 25 | 新决定无链接, 同报告留下多个绑定 |
| wrongSupersessionTarget | 25 | 目标位置 7 不存在, 旧绑定未被合法取代 |
| overbroadSupersession | 25 | 新决定未处置 Execution 2 报告, 却删除其原绑定 |
| supersessionRewritesOldDecision | 26 | 旧决定处置项由 3 变 2, 独立快照保持原值 |
| supersessionLinksNotCommitted | 25 | 命令保留原请求链接, 持久决定遗漏链接 |

20 组正常运行共 32,000 条抽样轨迹, 每条最多 100 步, 输入 seed 42, Quint 0.32.0 / Rust; 未发现所检查的 commandSafety /
conflictSafety 违规. 日志与 ITF 在 /tmp/beamlet-quint-q73-complete, 汇总日志 /tmp/beamlet-quint-q73-complete.log. 五个
Mix 工具测试、格式/编译与主动诊断检查通过. 开发期间的未完成检查及工具调用限时不算通过或预期反例.

新增 12 个正常场景覆盖遗漏/不存在/自身/已取代/越界引用拒绝、部分范围保留、原命令在 Open/Closed
下重投、并发取代及新证据使审查过期、两旧来源共同被取代和仅改变引用也构成命令内容冲突.
原有新版审查场景现在明确携带取代引用. 所有重新提出的自动/人工决定仍按实际权限、完整证据和契约核验,
没有在接收时补齐或改变请求.

以下每组各 1,000 条轨迹; “—”表示见证初始化已成立, 不用于证明新的保存. 计数可重叠, 不是事件次数、完整覆盖或统计证明:

| 冲突前缀 | 处置保存 | 全部排除保存 | 取代保存 | 成功终结 | 失败终结 |
| --- | ---: | ---: | ---: | ---: | ---: |
| conflictInit | 218 | 131 | 9 | 7 | 48 |
| queriedConflictInit | 67 | 0 | 0 | 67 | 0 |
| bothConflictsInit | 114 | 63 | 3 | 52 | 0 |
| resolvedConflictInit | — | 87 | 113 | 4 | 179 |
| allExcludedInit | — | — | 115 | 8 | 19 |
| partiallySupersededInit | — | — | — | 8 | 15 |

取代见证已从未初始化该目标的前缀到达. queriedConflictInit 没有对应完整排除契约集合, 不声称覆盖零命中的排除/取代路径.
初始化未知范围之后的成功/失败来自新的合格判断或证据, 不归因于原全部排除命令.
决定身份、最小引用要求、真实条件核验、归档/撤回和 SQL 并发仍未验证; 不宣称穷尽证明或 Liveness.

Q74 规则语义版本检查点: 通过 mix beamlet.check 完整检查. 八个入口类型检查覆盖 59 个 Quint 文件, 141/141 正常场景 (23 +
2 + 69 + 47) 与 49/49 mutation 检测场景通过. 全部 49 份 ITF 已读取, 每份仍只有原五组状态变量.
新增五条反例核对了实际引用版本、接受时定义、请求/决定差异、原命令结果和重投处理见证:

| 新反例 | 合法前缀步数 | 核对的违规 |
| --- | ---: | --- |
| ruleVersionIgnored | 21 | actorQualified=true, 但请求 v1 在接受时定义中不存在 |
| ruleConditionsFromOtherVersion | 21 | actorQualified=true, 指定 v2 要求查询来源, 实际主报告来自 Worker |
| automaticRequestVersionRefreshed | 23 | 原命令引用 v1, 实际持久决定引用 v2 |
| historicalRuleReinterpreted | 22 | 原决定/命令不变, 历史 v1 定义的 queryRequired 从 false 被改成 true |
| replayBlockedByRuleRetirement | 23 | 持久账本不变, 可读且已有原记录的重投被错误回复 CommandIneligible |

23 组正常运行共 35,000 条抽样轨迹, 每条最多 100 步, 输入 seed 42, Quint 0.32.0 / Rust.
jobs=4、threads=4、mutation_threads=1, 配置保存在 run-info.txt; 未发现所检查的 commandSafety / conflictSafety 违规.
日志与 ITF: /tmp/beamlet-quint-q74-final; 汇总日志: /tmp/beamlet-quint-q74-final.log. 十个 Mix
工具测试、格式、编译和主动诊断检查通过; 工具测试不计入 Quint 场景数.

新增 16
个正常场景覆盖多版本并存、同版本重复定义拒绝、当前审查但指定版本退役/未知、指定版本条件不足、原成功/拒绝结果在登记变化及
Closed 后重投、读取授权、同身份更换版本冲突、新身份明确 v2 求值、独立契约校验、新证据过期及人工入口. 抽象版本 0/9
场景检查未登记引用, 不代表缺失字段或真实格式校验已实现.

以下三个前缀各 1,000 条轨迹. “—”表示初始化已成立, 不作为新保存覆盖; 各列可重叠, 不是事件次数、完整覆盖或统计证明:

| 规则版本前缀 | v1 决定 | v2 决定 | 原命令重投 | 拒绝保存 |
| --- | ---: | ---: | ---: | ---: |
| automaticRulePendingInit | 165 | 1 | 993 | 1000 |
| automaticRuleCommittedInit | — | 1 | 996 | 1000 |
| retiredRuleRejectedInit | 96 | 0 | 996 | — |

该模拟在处理动作之间可以选择并存/仅 v2 的可信策略, 不建模不可逆的注册表迁移. retiredRuleRejectedInit 后续 v1
命中来自随后选择允许 v1 的策略与新身份, 不表示已保存拒绝被重新执行. v2 深路径命中少,
用确定场景核对其新身份、明确版本及契约. 历史解释快照是受信见证, 不证明真实规则定义、登记持久性或治理;
旧非终结处置在规则退役后的后续效力在 Q74 检查点尚未决议, Q75 已确认普通退役不自动撤销. 不宣称穷尽证明、Liveness、SQL
或外部效果恰好一次.

结构保持用户拆分后的依赖方向: 新规则逻辑在 logic/rules.qnt, 测试与 fixture 在 scenarios/repeating/rules_*.qnt,
故意错误在 mutations/rules.qnt, 主目录仅增加具体入口. 所有 Quint 文件不超过 200 行, 导入图无环, 八个入口覆盖全部文件,
正常模拟不导入测试或 mutation.

Q75 普通退役检查点: mix beamlet.check --log-dir /tmp/beamlet-quint-q75-complete 完整通过. 八个入口类型检查覆盖全部 62 个
Quint 文件, 151/151 正常场景 (23 + 2 + 79 + 47)、51/51 mutation 检测场景及实际反例通过. 全部 51 份 ITF 已读取,
仍恰好包含五组状态变量; 每条记录的合法前缀长度与实际 ITF 核对.

| 新反例 | 合法前缀步数 | 实际违规 |
| --- | ---: | --- |
| retirementClearsDisposition | 22 | 原决定/命令/报告/Outcome 不变, 接受时作用范围被改写, 实际适用绑定 1→0; 伪造 durableUnchanged=true 仍被检出 |
| retirementBumpsJudgmentRevision | 22 | 适用绑定与决定不变, 判断版本 8→9; 伪造摘要仍被实际版本比较及判断变化链检出 |

新增 10 个确定场景覆盖普通退役不改变 Open
处置/判断版本、旧排除处置仍支持合格失败终结、在途人工显式取代不因退役过期、新身份的退役版本拒绝、仅在途未接受请求不享有保留效力、原结果重投、Closed
后原 Outcome/命令保留、新证据仍使旧处置失效、退役另一版本不影响 v1 处置及 Coordinator 重启后保留.
这些不实现因缺陷撤销处置的命令.

26 组正常运行共 38,000 条抽样轨迹, 最多 100 步, 输入 seed 42, Quint 0.32.0 / Rust, jobs=4 / threads=4 /
mutation_threads=1; 未发现所检查的 commandSafety / conflictSafety 违规. 日志/ITF 在 /tmp/beamlet-quint-q75-complete,
汇总日志 /tmp/beamlet-quint-q75-complete.log, 配置与阶段/任务耗时在目录内. 十个 Mix
工具测试、格式、编译与主动文档/Elixir 诊断通过. Quint 无 LSP, 使用实际 CLI 检查.

退役扩展三个合法前缀各 1,000 条, 后续策略均不登记 v1. 以下为见证命中轨迹数, 可重叠; “—”表示初始化即成立,
不代表新事件覆盖. 绑定保留见证观察的是退役转换本身, 不要求后来有新证据仍保持同一适用范围:

| 退役前缀 | 退役后存在失败 Outcome | 退役当刻非空绑定保持 | 原命令重投 | 拒绝保存 |
| --- | ---: | ---: | ---: | ---: |
| ordinaryRetirementInit | 221 | — | 990 | 1000 |
| retirementBeforeDecisionInit | 8 | 0 | 990 | 1000 |
| retirementAfterClosureInit | — | 0 | 996 | 1000 |

retiredDispositionUsedWitness 的抽样谓词仅表示退役观察存在且结果为当前尝试的失败, 不单独证明终结沿用了旧规则处置.
retirementBeforeDecisionInit 尚无已接受旧决定, 其 8 条命中来自后来新的合格处置/证据; 旧处置支持终结的因果关系由
retiredDispositionStillAllowsEligibleFailureTest 确定场景核对. Closed 前缀的失败 Outcome 在初始化前已提交,
不作新终结覆盖. 零绑定保留命中分别来自退役时尚无处置、或 Closed 已使旧范围不适用, 不表明退役撤销了旧决定.

普通退役仍为可信策略输入边界与独立观察, 不实现真实注册表存储、分布式部署或治理事务. 62 个 Quint 文件全部不超过 200 行,
导入图无环, 正常入口不依赖测试/mutation, 核心五个状态变量保留. 该检查点尚未确认撤销既有处置的精确语义; Q76
随后确认不隐式恢复旧处置, 具体撤销协议仍待决议. 以上是轨迹受限的 Safety 抽样和具体故障检出,
不宣称穷尽证明、Liveness、真实契约/身份核验、SQL 并发或外部效果恰好一次.

Q76 范围撤销检查点: mix beamlet.check --log-dir /tmp/beamlet-quint-q76-complete 完整通过. 十个入口类型检查覆盖 68 个
Quint 文件, 173/173 正常场景 (23 + 2 + 79 + 69) 及 57/57 mutation 检测场景和实际反例通过. 全部 57 份 ITF 已读取,
每份仍包含五组状态变量, 反例表全部合法前缀步数与实际文件核对. 六个新反例还用独立脚本折叠显式引用,
核对绑定及原请求/报告/结果:

| 新反例 | 合法前缀步数 | 核对的实际违规 |
| --- | ---: | --- |
| withdrawalResurrectsOldTreatment | 28 | D1 旧取代链接被删除, 撤销后历史当前绑定 1→3, D0 两份旧排除错误复活; 原命令/报告/快照不变 |
| withdrawalOverstepsScope | 27 | 原请求撤销一报告, 实际决定撤销两报告, 当前绑定 3→1 而非保留两项 |
| withdrawalWithoutRevision | 27 | 撤销已保存、绑定移除, 版本仍为 10、判断变化链未更新 |
| uncheckedWithdrawalBasis | 27 | contractQualified=true, 实际接受时 withdrawalsAtDecision 为空 |
| withdrawalCreatesOutcome | 27 | 撤销命令原结果错误包含 Succeeded, 提交 sourceEligible=false |
| withdrawalDeletesEvidence | 27 | 原 reports 3→2, 成功报告被错误删除 |

新增 22 个确定场景覆盖撤销 D1 后不恢复
D0、部分撤销保留其他绑定、撤销采用不恢复旧排除、新身份重新采用旧结论、原处置及撤销命令重投、Closed
下原结果保留、新撤销在 Closed
拒绝、核验依据不足/旧目标/缺失/不存在/自身/已撤销引用拒绝、新证据与并发请求的过期审查、禁止撤销同时携带替代处置、两当前所有者、同
ID 改范围冲突、读取权限、入域前拒绝不占 ID 及 Coordinator 重启. 这是撤销效应的抽象协议示例,
不批准具体产品撤销权限、命令接口或 Closed 上的历史纠正方案.

29 组正常运行共 41,000 条抽样轨迹, 每条最多 100 步, 输入 seed 42, Quint 0.32.0 / Rust,
jobs=4、threads=4、mutation_threads=1; 未发现所检查的 commandSafety / conflictSafety / withdrawal entry safety 违规
(撤销入口 safety 代理 commandSafety). 日志及 ITF 在 /tmp/beamlet-quint-q76-complete, 汇总日志
/tmp/beamlet-quint-q76-complete.log; 配置/各任务及阶段耗时分别在 run-info.txt / timings.tsv. 十个 Mix
工具测试、格式、编译与主动文档/Elixir 诊断通过. Quint 通过实际 CLI 验证, 无 Quint LSP.

撤销三个定向前缀各 1,000 条, 下表为见证命中轨迹数, 各列可重叠; “—”表示初始化已成立, 不证明新执行覆盖:

| 撤销前缀 | 撤销接受 | 撤销后新判断 | 命令重投 | 失败终结 |
| --- | ---: | ---: | ---: | ---: |
| withdrawalPendingInit | 269 | 22 | 371 | 11 |
| withdrawnInit | — | 165 | 479 | 7 |
| partiallyWithdrawnInit | — | 156 | 467 | 8 |

renewedJudgmentWitness 表示已有撤销且新 ID 4 获接受, 不要求新结论与原结论相同; 相同旧结论的重新接受由
freshDecisionCanReestablishOldConclusionTest 单独核对. 命令重投是所有命令的通用见证, 不全归为撤销请求.
失败终结仍需独立资格/冲突判断, pending 前缀可能在撤销前经新合格决定终结, 不能把该列归因于撤销. 撤销命令本身返回无
Outcome 的原结果, 由确定场景与性质检查.

所有 Quint 文件不超过 200 行, 导入图无环, 正常模拟不导入测试/mutation; 五组状态与九个核心参数不增加.
独立绑定/依据见证不是执行屏障或获批 SQL 字段, 真实撤销授权、依据真实性、注册表治理、精确冲突相关性和 SQL 并发仍未验证.
完整抽样不是穷尽证明或 Liveness, 不证明外部效果恰好一次. 开发期的一次整组短轨迹工具调用限时终止, 不计作通过或不变量违反;
新撤销入口另经 Mix 调用实际短轨迹, 后以完整检查为最终记录.

Q77 撤销命令检查点: mix beamlet.check --log-dir /tmp/beamlet-quint-q77-complete 完整通过. 十个类型入口覆盖全部 70 个
Quint 文件, 185/185 正常场景 (23 + 2 + 79 + 81)、60/60 mutation 检测场景和实际反例通过.
最终类型与正常场景分别再次通过 /tmp/beamlet-quint-q77-final-types、/tmp/beamlet-quint-q77-final-tests.
全部 60 份 ITF 已读取, 五组状态变量及每条合法前缀步数与反例表核对; 三个新反例另外独立核对原请求、处理前后账本及显式绑定:

| 新反例 | 合法前缀步数 | 实际违规 |
| --- | ---: | --- |
| withdrawalReplayRetargetsNewDisposition | 31 | 原 ID 3 请求仍指向 D1/版本 10, 错误执行改指 D3/版本 12; 实际版本 12→13, 决定/命令各 4→5, D3 绑定 3→1 |
| commandIdentitySplitByOperationKind | 29 | 同 ID 3 同时保存撤销和全部排除两种命令, 版本 11→12、决定/命令各 3→4 |
| withdrawalReplyBeforeCommit | 27 | 原账本不变, 撤销关系/结果/审计未保存却回复 CommandCommitted; 判断版本仍为 10 |

本轮没有更改通用命令的首次处理/重投守卫或新增状态变量: 既有 commandRecordsUnique、commandExecutionMatchesRequest、
commandHandlingSound、commandRepliesSound、commandEffectsAtomic、judgmentRevisionSound 等性质已覆盖 Q77,
以新确定场景与受控错误检验其适用于撤销. 新增 12 个正常场景覆盖 W 撤销后新处置形成时的原结果重投、回复丢失/重启、
撤销依据或提交权限不再满足但仍可读、两种操作互换身份 (包括已保存拒绝)、改目标/版本内容冲突、依据改善仍返回原拒绝、
使用新身份重新提交、首次过期审查拒绝及关系/结果/审计/版本共同保存. 具体撤销权限与 Closed 历史纠正仍待决议.

30 组正常抽样共 42,000 条轨迹, 每条最多 100 步, 输入 seed 42, Quint 0.32.0 / Rust,
jobs=4、threads=4、mutation_threads=1; 未发现所检查的 Safety 违规. 全部日志/ITF 在 /tmp/beamlet-quint-q77-complete,
汇总日志 /tmp/beamlet-quint-q77-complete.log, 配置/耗时在 run-info.txt / timings.tsv. 十个 Mix 工具测试、格式、编译和
主动文档/Elixir 诊断通过; Quint 无 LSP, 以实际 CLI 验证. 开发期的定向筛选误匹配非测试定义、witness 参数错误及限时终止
不作为 Safety 违规、预期反例或完整通过; 以最终检查为准.

四个撤销前缀各 1,000 条; 下列为见证命中轨迹数, 可重叠, 均不是事件次数或穷尽覆盖:

| 撤销前缀 | 完整 W 的原结果重投 | 协调与撤销的身份冲突 |
| --- | ---: | ---: |
| withdrawalPendingInit | 24 | 309 |
| withdrawnInit | 188 | 743 |
| partiallyWithdrawnInit | 0 | 759 |
| renewedWithdrawalInit | 197 | 722 |

withdrawalOriginalReplayWitness 只计具体完整 W/withdrawalRecord 的原结果读取, 不是所有撤销请求; 部分前缀保存同 ID
不同内容, 所以完整 W 应返回身份冲突而非该原结果, 零命中不作为完整 W 重投覆盖. crossKindIdentityConflictWitness
要求已接受原命令与 请求恰好一侧为 WithdrawDisposition, 不把普通采用/排除之间的差异计入;
领域拒绝占用共同身份由确定场景覆盖. renewedWithdrawalInit 的撤销与后续新判断均在初始化已成立, 不作新动作覆盖.
该组原结果重投命中不要求新处置之后始终适用; 重投不转向仍适用新处置的因果关系由
withdrawalReplayAfterRenewedDispositionDoesNotRetargetTest 独立核对.

70 个 Quint 文件全部不超过 200 行, 导入图无环, 普通入口不导入测试/mutation, 共用未绑定 fixture 并只在外层绑定参数.
这是有界 Safety 抽样和具体错误检测, 不证明穷尽正确性、Liveness、真实鉴权/撤销依据核验、SQL 原子实现或外部效果恰好一次.

Q59/Q60 检查点的定向见证运行同样使用输入 seed 42, 每组 1,000 条、最多 100 步. 见证计数是命中目标的轨迹数,
不是事件总次数或统计证明:

| 合法前缀 | 关键见证 | 命中轨迹数 |
| --- | --- | ---: |
| strictTests:preparedInit | 新授权 / 续租 / Unknown / 替代 | 77 / 33 / 61 / 147 |
| strictTests:grantedInit | 收到许可 / 外部调用 / 资源完成 | 477 / 321 / 321 |
| strictTests:grantedInit | Worker Pending / Worker 完成报告 | 203 / 90 |
| strictTests:grantedInit | Waiting / Resolved / Succeeded / Failed | 79 / 213 / 7 / 3 |
| strictTests:grantedInit | Cancelled / 迟到报告 / 负面查询报告 | 990 / 737 / 618 |
| strictTests:grantedInit | 重发许可 / 丢弃重复许可 / 丢弃旧 incarnation 许可 | 342 / 82 / 107 |
| strictTests:grantedInit | 已存回执 / 重复报告确认 / 报告重发 | 54 / 258 / 63 |
| fencedTests:grantHeldInit | 资源未来排除 / 替代 / Succeeded | 442 / 13 / 15 |
| repeatingTests:replacementInit | 两次外部效果 / 迟到报告 / Succeeded | 263 / 957 / 8 |

每个主要正常 step 动作有正向见证, 在普通或合法定向前缀抽样中实际达到. Witness 未达到不能用通过不变量替代;
此处用定向前缀及确定场景补足. 冲突纯规则、假设检查、disabled action 检查单独列为确定场景.
不把初始化即成立的不变量当可达性见证.

Q59/Q60 检查点的重复风险定向运行未达到 Failed, 不构成该实例 Failed 路径的覆盖. Q61/Q62 已补充
bothKnownFailuresCanCloseTest, 验证所有相关尝试确定失败时的正向终结. oldSuccessBlocksOrdinaryFailureTest 与
failureThenOldSuccessStillBlocksTest 检查旧成功尚未协调时拒绝普通 Failed; oldSuccessDoesNotBlockCancellationTest
检查取消仍可接受. 新见证 oldSuccessWithCurrentFailureReached 在 replacementInit 的 100 条、最多 100 步抽样中达到 5 条,
输入 seed 42, 未发现 Safety 违规.

## 自查与后续更新

结构自查: 状态按五组记录/映射组织; 生命周期和业务分类使用 sum type; str marks 仅为观测标签, 不影响协议守卫. 消息无序;
所有正常动作给五个变量赋值, 没有 blanket stutter fallback; invalidMessageVariant 为 false 且完整赋值的禁用分支. 普通
step 包含核心动作; reconciliationStep 通过 stepWithReconciliation 加入协调动作, 由显式受控 policy 驱动; commandStep
另加入请求、接收和重投, 以 commandSafety 检查. 测试和 mutations 分文件, 正常模型无 run 场景.

已执行的 init、逐步动作、确定场景和抽样未发现正常规则违反所列 Safety 性质. 当前限制是协议语义覆盖:
完整冲突解除、身份绑定与真实权限/规则条件核验、完整失败策略、callback 认证/关联、SQL 原子实现及迁移.
不宣称穷尽证明、Liveness、Ecto 正确性或外部效果恰好一次.

后续确认更完整的失败、冲突或启动协议后, 先更新模型与守卫/场景/见证, 再更新实现. 模型与实现不一致时检查原因,
不为让实现通过而削弱已确认不变量.
