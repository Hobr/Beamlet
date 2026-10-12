# 故意错误规则的反例记录

这些反例来自独立 mutation 模块, 不表示正常模型发生了同样的违规. 每条前缀通过真实守卫从 init 到达, 并在每一步检查 safety;
最后执行一条故意错误规则. Quint 0.32.0 / Rust, 输入 seed 42, max-samples 1, max-steps 1. init 内的合法前缀会出现在 ITF
中, 因此实际状态数量大于两条.

| 模块 | 被破坏性质 | 前缀转换数 | 违规转换数 |
| --- | --- | ---: | ---: |
| duplicateOutcome | outcomeUnique | 9 | 1 |
| overwriteOutcome | outcomeImmutable | 9 | 1 |
| reviveExpiredLease | expirySticky | 5 | 1 |
| negativeQueryRetry | replacementsSafe | 9 | 1 |
| incarnationInheritance | invocationsAuthorized | 6 | 1 |
| grantAfterClosure | startupsQualified | 3 | 1 |
| pendingRegression | resolvedKnowledgeCoherent | 10 | 1 |
| unknownFailure | commitsQualified | 7 | 1 |
| earlyReceipt | receiptsOnlyForStored | 8 | 1 |
| oldSuccessFailure | failureRespectsOldSuccess | 20 | 1 |
| unauthorizedReconciliation | reconciliationQualified | 20 | 1 |
| unregisteredReconciliation | reconciliationQualified | 20 | 1 |
| staleReconciliation | reconciliationQualified | 22 | 1 |
| permanentReconciliation | failureRespectsOldSuccess | 23 | 1 |
| silentlyRefreshedCommand | commandExecutionMatchesRequest | 23 | 1 |
| replayExecutedAgain | commandRecordsUnique | 23 | 1 |
| overwrittenCommand | commandRecordsImmutable | 23 | 1 |
| replayWithLatestResult | commandRepliesSound | 24 | 1 |
| earlyCommandReply | commandRepliesSound | 21 | 1 |
| replayRejectedAsStale | commandHandlingSound | 25 | 1 |
| rejectedCommandExecutedAgain | commandRecordsUnique | 23 | 1 |
| rejectionContextOverwritten | rejectedCommandsImmutable | 27 | 1 |
| resultReadPermissionIgnored | commandReadAuthorized | 23 | 1 |
| cachedResultRequiresSubmitPermission | commandHandlingSound | 23 | 1 |
| permissionDenialStoredAsDomainRejection | rejectionQualified | 21 | 1 |
| rejectionReplyBeforeStorage | commandRepliesSound | 21 | 1 |
| dispositionWithoutRevision | judgmentRevisionSound | 20 | 1 |
| heartbeatBumpsJudgmentRevision | judgmentRevisionSound | 20 | 1 |
| evidenceWithoutRevision | judgmentRevisionSound | 20 | 1 |
| judgmentRevisionReset | judgmentRevisionSound | 20 | 1 |
| incompleteConflictCoverage | conflictCoverageSound | 23 | 1 |
| uncheckedConflictBasis | conflictCoverageSound | 23 | 1 |
| erasedConflictHistory | conflictHistoryPreserved | 24 | 1 |
| terminalBeforeConflictResolution | terminalConflictsResolved | 23 | 1 |
| permanentConflictDisposition | terminalConflictsResolved | 26 | 1 |
| earlyConflictReply | commandRepliesSound | 23 | 1 |
| deletedConflictReport | reconciledEvidencePreserved | 24 | 1 |
| excludedAllUsesCachedKnowledge | commitsQualified | 24 | 1 |
| excludedAllCreatesOutcome | allExcludedCommitSound | 23 | 1 |
| implicitSupersession | supersessionLinksSound | 25 | 1 |
| wrongSupersessionTarget | supersessionLinksSound | 25 | 1 |
| overbroadSupersession | supersessionLinksSound | 25 | 1 |
| supersessionRewritesOldDecision | decisionsImmutable | 26 | 1 |
| supersessionLinksNotCommitted | commandExecutionMatchesRequest | 25 | 1 |
| ruleVersionIgnored | automaticRuleVersionsSound | 21 | 1 |
| ruleConditionsFromOtherVersion | automaticRuleVersionsSound | 21 | 1 |
| automaticRequestVersionRefreshed | commandExecutionMatchesRequest | 23 | 1 |
| historicalRuleReinterpreted | automaticRuleVersionsSound | 22 | 1 |
| replayBlockedByRuleRetirement | commandHandlingSound | 23 | 1 |
| retirementClearsDisposition | ordinaryRuleRetirementSound | 22 | 1 |
| retirementBumpsJudgmentRevision | ordinaryRuleRetirementSound | 22 | 1 |
| withdrawalResurrectsOldTreatment | withdrawalScopeSound | 28 | 1 |
| withdrawalOverstepsScope | commandExecutionMatchesRequest | 27 | 1 |
| withdrawalWithoutRevision | judgmentRevisionSound | 27 | 1 |
| uncheckedWithdrawalBasis | withdrawalScopeSound | 27 | 1 |
| withdrawalCreatesOutcome | withdrawalCommandsNonterminal | 27 | 1 |
| withdrawalDeletesEvidence | reconciledEvidencePreserved | 27 | 1 |
| withdrawalReplayRetargetsNewDisposition | commandHandlingSound | 31 | 1 |
| commandIdentitySplitByOperationKind | commandRecordsUnique | 29 | 1 |
| withdrawalReplyBeforeCommit | commandRepliesSound | 27 | 1 |

## duplicateOutcome

- 违规前: Intent=Closed; current=1; clock=0; outcomes=[OutcomeSucceeded]; commits=1; invocations=1;
  receipts-in-flight=1; E1: Resolved/SuccessKnown, generation=1, invalidated=false, grant=StartGrant.
- 违规后: Intent=Closed; current=1; clock=0; outcomes=[OutcomeSucceeded, OutcomeCancelled]; commits=2; invocations=1;
  receipts-in-flight=1; E1: Resolved/SuccessKnown, generation=1, invalidated=false, grant=StartGrant.

### overwriteOutcome

- 违规前: Intent=Closed; current=1; clock=0; outcomes=[OutcomeSucceeded]; commits=1; invocations=1;
  receipts-in-flight=1; E1: Resolved/SuccessKnown, generation=1, invalidated=false, grant=StartGrant.
- 违规后: Intent=Closed; current=1; clock=0; outcomes=[OutcomeCancelled]; commits=1; invocations=1;
  receipts-in-flight=1; E1: Resolved/SuccessKnown, generation=1, invalidated=false, grant=StartGrant.

### reviveExpiredLease

- 违规前: Intent=Open; current=1; clock=0; outcomes=[]; commits=0; invocations=0; receipts-in-flight=0; E1:
  Prepared/NoKnowledge, generation=1, invalidated=true, grant=NoGrant.
- 违规后: Intent=Open; current=1; clock=0; outcomes=[]; commits=0; invocations=0; receipts-in-flight=0; E1:
  Prepared/NoKnowledge, generation=1, invalidated=false, grant=NoGrant.

### negativeQueryRetry

- 违规前: Intent=Open; current=1; clock=2; outcomes=[]; commits=0; invocations=0; receipts-in-flight=1; E1:
  Unknown/NoKnowledge, generation=1, invalidated=true, grant=StartGrant.
- 违规后: Intent=Open; current=2; clock=2; outcomes=[]; commits=0; invocations=0; receipts-in-flight=1; E1:
  Unknown/NoKnowledge, generation=1, invalidated=true, grant=StartGrant; E2: Prepared/NoKnowledge, generation=0,
  invalidated=true, grant=NoGrant.

### incarnationInheritance

- 违规前: Intent=Open; current=1; clock=0; outcomes=[]; commits=0; invocations=0; receipts-in-flight=0; E1:
  StartAuthorized/NoKnowledge, generation=1, invalidated=false, grant=StartGrant.
- 违规后: Intent=Open; current=1; clock=0; outcomes=[]; commits=0; invocations=1; receipts-in-flight=0; E1:
  StartAuthorized/NoKnowledge, generation=1, invalidated=false, grant=StartGrant.

### grantAfterClosure

- 违规前: Intent=Closed; current=1; clock=0; outcomes=[OutcomeCancelled]; commits=1; invocations=0;
  receipts-in-flight=0; E1: Prepared/NoKnowledge, generation=1, invalidated=false, grant=NoGrant.
- 违规后: Intent=Closed; current=1; clock=0; outcomes=[OutcomeCancelled]; commits=1; invocations=0;
  receipts-in-flight=0; E1: StartAuthorized/NoKnowledge, generation=1, invalidated=false, grant=StartGrant.

### pendingRegression

- 违规前: Intent=Closed; current=1; clock=0; outcomes=[OutcomeSucceeded]; commits=1; invocations=1;
  receipts-in-flight=1; E1: Resolved/SuccessKnown, generation=1, invalidated=false, grant=StartGrant.
- 违规后: Intent=Closed; current=1; clock=0; outcomes=[OutcomeSucceeded]; commits=1; invocations=1;
  receipts-in-flight=1; E1: Waiting/SuccessKnown, generation=1, invalidated=false, grant=StartGrant.

### unknownFailure

- 违规前: Intent=Open; current=1; clock=2; outcomes=[]; commits=0; invocations=0; receipts-in-flight=0; E1:
  Unknown/NoKnowledge, generation=1, invalidated=true, grant=StartGrant.
- 违规后: Intent=Closed; current=1; clock=2; outcomes=[OutcomeFailed]; commits=1; invocations=0; receipts-in-flight=0;
  E1: Unknown/NoKnowledge, generation=1, invalidated=true, grant=StartGrant.

### earlyReceipt

- 违规前: Intent=Open; current=1; clock=0; outcomes=[]; commits=0; invocations=1; receipts-in-flight=0; E1:
  StartAuthorized/NoKnowledge, generation=1, invalidated=false, grant=StartGrant.
- 违规后: Intent=Open; current=1; clock=0; outcomes=[]; commits=0; invocations=1; receipts-in-flight=1; E1:
  StartAuthorized/NoKnowledge, generation=1, invalidated=false, grant=StartGrant.

### oldSuccessFailure

- 合法前缀: 调用方接受重复风险, 第一尝试到期后替代为 E2. 保存 E1 的成功报告, 再保存 E2 的失败报告. 两个尝试都有确定结果,
  Intent 保持 Open, current=2, 两份原始证据均保留.
- 故意错误规则: 只检查当前失败和没有 Unknown, 忽略尚未协调的旧成功证据, 提交 OutcomeFailed.
- 违规后: Intent=Closed; outcomes=[OutcomeFailed]; commits=1; oldSuccessAtCommit=true. 独立的 failureRespectsOldSuccess
  在提交当刻检出违规.
- 该检查不要求后来才到达的成功报告追溯推翻已有 Outcome; 见证记录的是提交前已经保存的证据. 本反例采用独立的重复风险实例,
  不改变其他 mutation 的禁止重复前提.

### unauthorizedReconciliation / unregisteredReconciliation

- 合法前缀同 oldSuccessFailure, 已存旧成功和当前失败, Intent Open.
- 故意错误规则绕过主体守卫, 分别保存 Operator(2) 的决定或未登记规则身份 3 / 语义版本 1 的自动决定 (Q74 前使用
  AutomaticRule(3) 抽象).
- 违规后: reports=2; decisions 从 0 变为 1; actorQualified=false, contractQualified=true. 即使契约依据与证据快照合格,
  主体或规则未获授权仍不能接受决定.

### staleReconciliation

- 合法前缀在原两份报告后保存新的查询成功报告, reports=3.
- 故意错误规则提交只审查原两份报告的决定.
- 违规后: decisions 从 0 变为 1; 主体与契约条件合格, 但 reviewedRevision=7 与 acceptedRevision=8 不同,
  reconciliationQualified 检出过期快照.

### permanentReconciliation

- 合法前缀先提交精确作用域内的有效排除决定, 后收到新的查询成功证据. 原决定历史仍保留, 原始 reports 从 2 增至 3,
  旧处置不再直接解除新证据阻塞.
- 故意错误规则将“曾经有协调决定”视为永久已协调, 提交 OutcomeFailed.
- 违规后: decisions=1; outcomes=[OutcomeFailed]; oldSuccessAtCommit=true. failureRespectsOldSuccess
  检出未经新审查的失败终结.

### silentlyRefreshedCommand

- 旧人工请求审查两份报告, 提交前第三份查询成功报告到达.
- 故意错误规则自动更新审查快照并执行排除, 却将旧请求保存为原命令.
- 违规后: commands 0 → 1, decisions 0 → 1; 原请求 reviewedRevision=7, 实际决定 reviewedRevision=8.
  主体与新决定本身可以合格, 但 commandExecutionMatchesRequest 检出人工请求被静默改义.

### replayExecutedAgain / overwrittenCommand

- 合法前缀已提交排除命令, 同一原请求再次在途, commands=1, decisions=1.
- 重执行规则绕过重投查找, commands 1 → 2, decisions 1 → 2, 同一 ID 被再次提交.
- 改写规则保持记录数量 1, 却把原排除请求改为采用请求, 独立原记录见证不变. commandRecordsImmutable 检出内容覆盖.
- 两种规则都改变持久账本, 违反已提交命令的重投只返回原结果.

### replayWithLatestResult

- 原命令仅提交排除决定, 原处理结果 outcomes=[]; 后续普通失败使 Intent Closed / OutcomeFailed.
- 故意错误规则以当前 OutcomeFailed 替换重投回复中的原结果, 不改持久账本.
- 回复与持久命令记录不同, commandRepliesSound 检出错误. 当前 Intent 状态与原命令处理结果必须分开.

### earlyCommandReply

- 原请求已发送, 尚无任何协调决定或命令记录.
- 故意错误规则发送 CommandCommitted, commands 与 decisions 都保持 0.
- commandRepliesSound 检出没有持久提交记录的成功回复.

### replayRejectedAsStale

- 原排除命令已提交, 后收到新查询报告, 原请求再投.
- 故意错误规则先检查当前快照, 返回 CommandStale, 不改持久账本.
- 普通证据/唯一性性质仍可成立; 处理时的独立见证记录 previous=1 且请求与原记录相同, commandHandlingSound
  检出将已提交重投当作新请求拒绝.

### rejectedCommandExecutedAgain

- 原命令因契约条件不满足而提交领域拒绝, 后续条件已满足, 原请求再次在途.
- 故意错误规则忽略拒绝记录, 用同一 ID 保存成功命令并执行排除.
- 违规后: accepted 0 → 1, rejected 保持 1; 同一 ID 在两类结果中同时存在. commandRecordsUnique 检出跨分类身份重复.

### rejectionContextOverwritten

- 过期审查拒绝已保存当时三份报告的上下文; 新查询使当前报告集合增至四份, 原请求重投.
- 故意错误规则以当前四份报告替换原拒绝, 原拒绝见证不变.
- rejectedCommandsImmutable 检出原结果覆盖; 重投必须返回原处理时刻的上下文.

### resultReadPermissionIgnored / cachedResultRequiresSubmitPermission

- 合法前缀已提交排除命令, 原请求重投.
- 第一条错误规则在 mayRead=false 时返回 CommandCommitted; 持久账本未变, commandReadAuthorized 检出内容返回缺少读取授权.
- 第二条在 mayRead=true、maySubmit=false 时返回 CommandForbidden; 原记录和请求一致, commandHandlingSound
  检出错误要求提交权限才能读取原结果.

### permissionDenialStoredAsDomainRejection

- 新请求本身满足协调条件, 但当前提交权限不足.
- 故意错误规则提交 DecisionIneligible 拒绝记录, 占用命令 ID.
- 违规后: rejected 0 → 1, admitted=false, eligible=true. rejectionQualified 检出入域前权限失败被错误固定为领域拒绝.

### rejectionReplyBeforeStorage

- 新请求获准进入领域处理, 契约条件不满足.
- 故意错误规则返回 CommandIneligible 而不提交任何拒绝记录.
- rejected 保持 0; commandRepliesSound 检出没有持久原结果的领域拒绝回复.

### dispositionWithoutRevision / evidenceWithoutRevision

- 合法前缀保留旧成功与当前失败, 当前 revision=7.
- 两条错误规则分别保存协调处置或新查询报告, 但把版本留在 7.
- 独立变化链记录了相关变化和 next=8, judgmentRevisionSound 检出当前版本与变化链不一致.

### heartbeatBumpsJudgmentRevision

- 合法前缀处于 revision=7, 当前尝试 lease 可续租.
- 故意错误规则完成普通续租后把版本改为 8, 判断投影与独立变化链没有相关变化.
- judgmentRevisionSound 检出心跳误增版本.

### judgmentRevisionReset

- 合法前缀处于 revision=7.
- 故意错误规则保存新查询证据后将 revision 重置为 0, 并清空变化链.
- 当前判断投影与 initialLedger 不同, judgmentRevisionSound 检出重置后无法解释的状态.

### incompleteConflictCoverage / uncheckedConflictBasis

- Q71 防御性合法前缀显式允许已核验入口提交矛盾查询报告, 保存旧成功、其矛盾失败及当前失败, revision=8, reports=3.
- 第一条错误规则只保存对旧成功的采用, 遗漏矛盾失败报告: coverageQualified=false, evidenceQualified=true.
  它特意提供可通过逐项契约校验的输入, 独立验证覆盖检查不能省略. 第二条覆盖两份相关报告, 却在没有已核验处置依据时提交:
  coverageQualified=true, evidenceQualified=false.
- 两者都把 decisions 从 0 增至 1; conflictCoverageSound 分别检出覆盖或依据不足.

### erasedConflictHistory / deletedConflictReport

- 合法前缀已完整提交排除协调, reports=3, decisions=1, commands=1, 历史 conflict=true, 当前对应阻塞已解除.
- 清除规则把历史 conflict 改为 false; conflictHistoryPreserved 检出与仍保留的原始矛盾报告不一致.
- 删除规则把矛盾失败从原报告中移除, reports 3 → 2; 独立接受时证据见证不变, reconciledEvidencePreserved 检出删证据.

### terminalBeforeConflictResolution / permanentConflictDisposition

- 第一条在尚无冲突处置时直接提交 OutcomeFailed. 第二条先合法处置两份报告, 后收到新的成功报告, 原处置不再适用,
  却仍提交失败.
- terminalConflictsResolved 根据提交当刻的独立 conflictsAtCommit=true 检出未经解除阻塞的成功/失败终结,
  不用未来报告追溯推翻已提交结果.

### earlyConflictReply

- 新冲突请求在途, 尚无命令记录、协调决定或 Outcome.
- 故意错误规则返回 CommandCommitted, durable 保持不变.
- commandRepliesSound 检出没有原子持久结果的成功回复.

上述 Q71 前缀放宽来源一致性以检查防御性处理; 不是声称正常资源生成器产生了矛盾事实. 整组契约依据依然是受信、已核验输入,
不是客户端声明.

### excludedAllUsesCachedKnowledge

- 合法前缀已明确排除成功与失败报告, 本次判断未知, 已授权未知风险仍在.
- 故意错误规则绕过当前判断, 以历史 Knowledge 当作充分依据提交普通 Failed.
- commitsQualified 检出提交时来源不合格; 无冲突阻塞不等于没有未知风险.

### excludedAllCreatesOutcome

- 合法前缀中全部排除命令在途, 尚未执行决定.
- 故意错误规则把该非终结处置当作成功采用, 同时保存命令与成功 Outcome.
- allExcludedCommitSound 检出该命令错误产生终结结果; 原始证据仍完整, 不是通过删除报告制造反例.

### implicitSupersession / wrongSupersessionTarget

- 合法前缀已有一项完整处置, 新取代命令在途.
- 故意错误规则接受遗漏引用或引用不存在决定的新处置, 并将 supersessionQualified 伪造为 true.
- supersessionLinksSound 根据接受前缀检查实际目标与覆盖, 不依赖该布尔值即认定合格; 旧绑定未被明确取代时,
  dispositionBindingsUnique 也能检出同报告多个当前绑定.

### overbroadSupersession

- 旧决定处置三份报告; 新请求只重新处置其中两份.
- 故意错误规则把第三份报告也加入取代范围, 并伪造 admission bool.
- supersessionLinksSound 检出引用范围超出新决定的报告集合. 第三份报告的原排除不能被顺带撤销, 否则历史 FailureKnown
  可能重新影响当前判断.

### supersessionRewritesOldDecision

- 合法前缀已完成部分范围取代, 旧决定及其命令仍保留.
- 故意错误规则改写旧决定的证据处置集合, 不改变其列表位置.
- decisionsImmutable 对照独立 decisionSnapshots 检出历史值变化; 该见证不作执行守卫, 不是 SQL 字段或表.

### supersessionLinksNotCommitted

- 新请求明确携带取代链接.
- 故意错误规则在持久决定中丢弃链接, 却用原请求保存命令结果.
- commandExecutionMatchesRequest 检出命令和实际决定的取代引用不一致, 不能把丢失链接的写入视为原请求已经完整处理.

### ruleVersionIgnored / ruleConditionsFromOtherVersion

- 合法前缀已有旧成功和当前失败, 指定规则版本的请求在途.
- 第一条错误规则仅按规则身份接受已退役 v1; 第二条以 v1 条件接受指定 v2 的 Worker 报告, 但 v2 要求查询来源.
- 两条都伪造 actorQualified=true. automaticRuleVersionsSound 检查实际引用及接受时定义,
  分别检出版本未登记和指定版本条件不满足.

### automaticRequestVersionRefreshed

- 查询成功报告已保存, v1 请求在途; 处理时只有 v2 登记, v2 条件与契约本身可以满足.
- 错误规则把实际执行决定迁移到 v2, 却用 v1 原请求保存命令.
- commandExecutionMatchesRequest 检出规则版本被静默改义, 即使新的 v2 决定本身合格也不能冒充原请求执行成功.

### historicalRuleReinterpreted

- 合法前缀已接受 v1 的 Worker 报告排除决定, 原决定和命令均保留.
- 错误规则修改接受时 v1 定义快照, 用新增“必须查询来源”的条件重新解释历史, actorQualified 仍保持 true.
- automaticRuleVersionsSound 检出原接受事实与被改写解释不一致; 当前登记变更不能替换历史解释材料.

### replayBlockedByRuleRetirement

- v1 命令已处理且原请求重投, 处理时 v1 已退役, 只有 v2 登记.
- 错误规则重新检查登记后返回 CommandIneligible, 持久账本保持不变.
- commandHandlingSound 检出已处理请求被当作新提交; 当前读取权限仍需校验, 但退役不让原命令重新执行或失去原结果身份.

### retirementClearsDisposition

- 合法前缀已接受 v1 的非终结排除处置, Intent Open, 原成功报告当前被排除.
- 错误规则把普通退役当作撤销, 改写接受时作用范围, 使原适用绑定消失; 原决定内容、命令结果及原报告未改.
- 即使伪造 durableUnchanged=true, ordinaryRuleRetirementSound 仍比较实际前后绑定并检出丢失. 该见证只观察退役转换,
  不阻止后来新证据或显式取代合法改变绑定.

### retirementBumpsJudgmentRevision

- 同一合法前缀中, 普通退役没有新增判断材料或改变当前处置.
- 错误规则递增 Judgment Revision, 同样伪造 durableUnchanged=true.
- ordinaryRuleRetirementSound 从实际前后版本检出误增; judgmentRevisionSound 也独立检出版本与判断变化链不一致.

### withdrawalResurrectsOldTreatment

- 合法前缀中 D0 三报告排除, D1 显式取代其中两报告, 随后合法撤销 D1 的两报告范围; D0 只有范围外第三报告继续有效.
- 错误规则删除 D1 的历史取代链接, 把撤销误做历史回退; D0 的两项旧排除重新出现, 原报告/命令/撤销记录保留.
- withdrawalScopeSound 对照撤销接受时独立绑定快照与实际前缀, 检出历史回退; decisionsImmutable
  和请求/决定一致性也不允许改写 D1 的链接.

### withdrawalOverstepsScope

- 请求只撤销 D1 的 success1 范围, 错误规则实际撤销其两报告, 却按原部分请求保存命令.
- commandExecutionMatchesRequest 检出作用范围改义; 范围外本应保留的 disputedFailure 采用绑定被错误删除.

### withdrawalWithoutRevision

- 错误规则合法保存撤销关系与命令, 却保留原判断版本和变化链.
- judgmentRevisionSound 检出实际判断材料已改变但未递增版本; 这会让其他在途审查误以为仍然当前.

### uncheckedWithdrawalBasis

- 明确撤销引用结构本身有效, 但接受时可信策略没有核验该撤销范围/依据.
- 错误规则把 contractQualified 伪造为 true. withdrawalScopeSound 检查实际 withdrawalsAtDecision,
  不接受仅靠布尔标志掩盖的未核验撤销.

### withdrawalCreatesOutcome

- 错误规则在撤销时同时提交 Succeeded, 原命令结果因此包含终结 Outcome.
- withdrawalCommandsNonterminal 检出“撤销就是成功”; 原终结资格和命令结果检查也保持独立.

### withdrawalDeletesEvidence

- 错误规则保存撤销关系后删除原成功 Report, 把撤销当前处置误作清除原始证据.
- reconciledEvidencePreserved 检出接受时原报告丢失; 撤销后必须仍能重新判断原始证据.

### withdrawalReplayRetargetsNewDisposition

- 合法前缀已保存 D0、D1、撤销 W 和新处置 D3; 原 W 的重投请求明确在途, 仍引用 D1、审查版本 10.
- 错误规则重新指定 D3 两份报告、把审查版本改为 12, 再以同 ID 3 执行. 新范围在给定可信核验事实下可以撤销,
  但这不是原请求. 实际版本 12→13、决定/命令各 4→5, D3 当前绑定 3→1; 原 reports/Outcome 不变.
- commandHandlingSound 检出已知原请求处理却改变 Durable 并返回改义的新结果; 请求身份唯一性也被破坏.

### commandIdentitySplitByOperationKind

- 合法前缀已保存 ID 3 的撤销结果, 随后同 ID 的协调请求明确到达. 新协调的证据/契约/版本本身合格,
  但该身份已被撤销占用.
- 错误规则把另一操作种类的已占用身份当作新身份, 绕过共同身份查找并接受请求. 同 ID 3 出现 WithdrawDisposition /
  ExcludeAllEvidence 两份命令记录, 版本 11→12, 决定/命令各 3→4.
- commandRecordsUnique 检出共同身份域破坏; 权威处理也应返回身份冲突而非重新执行.

### withdrawalReplyBeforeCommit

- 原撤销请求明确在途, 但只有两个旧决定及命令; W 的关系/原结果/审计尚未保存, 版本为 10.
- 错误规则账本完全不变却发送 CommandCommitted(withdrawalRecord). commandRepliesSound 检出回复中原记录不存在;
  不是靠解析错误或无效退出码冒充反例.

## 正常闭环补全的七条反例

以下实际 ITF 来自 `/tmp/beamlet-normal-completion-full`, Quint 0.32.0 / Rust,
输入 seed 42、max-samples=1、max-steps=1、mutation_threads=1.
每份 ITF 已解码并核对违规前后的实际记录, 恰好包含原五组变量与新 usage 六组状态.
前缀步数按 `states.length - 2` 核对; 先有合法前缀, 再执行一条故意错误转换.

| 模块 | 被破坏性质 | 合法前缀步数 | 核对的实际变化 |
| --- | --- | ---: | --- |
| normalWrongResultValue | outcomeValuesEvidenced | 10 | 原报告 value=1, Outcome/firstOutcome/commit 均伪造为 9, 仍被独立业务值检查检出 |
| normalDefinitionOverwritten | submissionIdentitySound | 2 | 目录定义 input 从 1 改为 9, 独立 creation 原定义仍为 1 |
| normalCallbackBindingLost | handlerLaunchesSound | 8 | 已外部调用后持久 CallbackBinding 被改为 NoCompletion, launch 快照保留原关联 |
| normalExpiredIdempotencyRetry | retryContractsSound | 12 | 契约时间 4、窗口只到 3, current 仍错误从 Execution 1 切换到 2 |
| normalSuccessNotAtomic | normalAcceptanceAtomic | 10 | 成功报告入账, 但 Outcome 未保存且 Intent 仍 Open |
| normalContextChanged | handlerLaunchesSound | 8 | Handler context 从 1 改为 9, 原 launch context 保持 1 |
| normalFailureNotAtomic | normalAcceptanceAtomic | 10 | 失败报告入账但未终结, 伪造 stop=false; 原定义仍为 StopOnFailure, 独立策略重算检出 |

错误结果反例同时改写 firstOutcome 与 commit, 不能仅依赖首值相等来检出;
失败反例同时伪造停止摘要, 不能仅相信该布尔值. 其余六十条反例仍从原专用入口复跑,
新 mutation 不进入正常 profile, 不把这些故意违规描述为正常模型发现的 bug.

单条新增反例可复现为:

```sh
quint run model/quint/beamletNormalUse_mutations_test.qnt --main normalWrongResultValue \
  --init mutantInit --step mutantStep --invariant mutantInvariant \
  --max-samples 1 --max-steps 1 --seed 42 --backend rust --n-threads 1 \
  --out-itf /tmp/normal-wrong-result.itf.json
```

## 执行核心隔离后的反例回归

原 67 条在 `/tmp/beamlet-model-convergence-full` 全部产生预期违规, ITF 均已解码并核对实际状态变化.
执行九条和 oldSuccessFailure 现依赖独立核心, 原名称/BUG/指定性质保留; 其余协调/治理反例仍在组合参考.
正常七条在最终增量检查中再次检出, 并新增以下第八条, 当前总计 68 条.

| 模块 | 被破坏性质 | 合法前缀步数 | 核对的实际变化 |
| --- | --- | ---: | --- |
| normalExtendedIdempotencyWindow | retryCallsOriginalContract | 17 | 原窗口到 3、新声明到 6、contractTime=4; 错误调用使 invocations/launches 从 1 增至 2, 原 binding 不变 |

新 ITF 位于 `/tmp/beamlet-convergence-final/normalExtendedIdempotencyWindow.itf.json`, 共 19 个状态、六组变量.
错误动作只绕过调用契约守卫, 保留真实授权、原定义/上下文和调用观察; 独立性质比较调用时间与旧窗口.
这是本轮修复前确实可复现的模型漏洞: `newHandlerCannotExtendOriginalWindowTest` 修复前失败、修复后通过.
修复后正常授权/调用同时受原窗口和当前窗口限制, 不能仅靠部署的新声明延长旧外部 key 保证.

```sh
quint run model/quint/beamletNormalUse_mutations_test.qnt --main normalExtendedIdempotencyWindow \
  --init mutantInit --step mutantStep --invariant mutantInvariant \
  --max-samples 1 --max-steps 1 --seed 42 --backend rust --n-threads 1 \
  --out-itf /tmp/normal-extended-window.itf.json
```

完整 ITF 由 [Mix 检查器](../../tools/beamlet/quint_checks.ex) 写入日志目录. 全部复跑:

```console
mix beamlet.check --phase mutations --log-dir /tmp/beamlet-counterexamples
```

单条反例也可用 Quint CLI 复现:

```sh
quint run model/quint/beamletCore_mutations_test.qnt --main negativeQueryRetry \
  --init mutantInit --step mutantStep --invariant mutantInvariant \
  --max-samples 1 --max-steps 1 --seed 42 --backend rust \
  --out-itf /tmp/negative-query-retry.itf.json
```

预期退出码 1 且报告 Invariant violated. parse/typecheck/runtime 错误不算预期反例. 这些 mutation 覆盖特定守卫,
不代表已进行全面 mutation 测试.
