# 覆盖审计

当前主结果是[核心 C1–C6 组合](core/verification-report.md)。本文件保留范围缩减前的 R/S/P 与88行源矩阵，只作历史/补充映射，不能用行数替代当前核心问题或未完成 BMC。用户缩减旧全契约目标是明确范围变更，不表示原 AC 门禁已通过。

“抽象内覆盖”指对应旧模型断言与确定路径覆盖，不是无界证明或实际实现；“部分覆盖”保留缺失条款；“待运行时验证”须真实代码/平台/数据证据。下列初期映射按原检查点保留；后续保真修复另列，不把旧 gap probe 通过算作修复验收。

所有 evidence 都只在本地、Git 忽略，包括 compact pack。新检出从报告、[源码](architecture.qnt)和[历史命令说明](README.md)理解结果并生成新证据，不能独立查看未提交的旧日志/哈希文件。原 source line 归属旧快照，当前契约按链接读取；本轮没有模型/测试/运行时变化或昂贵重跑。

<a id="independent-review-qualification"></a>
<a id="retry-checkpoint-qualification-historical"></a>

## 历史检查阶段的限定

重试阶段六 typecheck、53旧场景/13协议/9负控通过；500条/depth60/seed20261010 只是诊断，完整组合 depth1 在 JSON serializer 失败。独立检查阶段修复捕获/失败前态/结果回复原子性/G08分类后，七 typecheck/82测试通过，其中三个坏行为 gap probe 仍不计修复验收。三组各10,000抽样无采样反例：default/recovery完整step depth60，条件调度depth40；恢复消费分别0/17/10,000。默认0仍是缺口，fixture与同一路径重复不是一般活性。后续保真模型依赖变化，旧抽样不能验证新源；最终97确定测试/九typecheck也没有完成组合界限。精确阶段、哈希与超时见[历史报告](verification-report.md)。

<a id="indexed-requirements-18"></a>

## 初期需求映射（18项，历史）

| ID | 场景 | 模型证据 | 状态与剩余边界 |
| --- | --- | --- | --- |
| R1 | S1/S6 | G07；共享不透明状态/类型 | 部分覆盖：两种不透明 Definition 后来已建模，真实依赖检查仍未执行 |
| R2 | S1/S2 | G04; fullSystemTest, twoEffectFifoTest | 部分覆盖：应用/facade 实际载荷集成未执行 |
| R3 | S3 | hostLossTest; G01/G02/G04 | 部分覆盖：原子权威与远程监督为前提 |
| R4 | S5 | finishLastReplyTest, invalidFinishTest, failedLateResultTest | 部分覆盖：真实步骤故障/预算为抽象 |
| R5 | S15 | uiIndependenceTest; G01 | 部分覆盖：真实包装与设备/网络支持未验证 |
| R6 | S4 | precommitLossTest, replacementOwnerTest, receiptAfterControlTest | 部分覆盖：非输入回执后来加入；没有磁盘/崩溃实现证明 |
| R8 | S2 | G04; fifoContinuationTest, twoEffectFifoTest, obsoleteEvaluatedUnknownTest | 部分覆盖：独立输入键加入；真实工作进程恢复未验证 |
| R9 | S9 | providerUnavailableTest; generation/domain 选择 | 部分覆盖：Scope 父级/资源生命周期为抽象 |
| R10 | S10 | authorityUnavailableTest; G01/G02 | 部分覆盖：单权威前提；Ra/quorum/磁盘待验证 |
| R11 | S11 | G03; recoveryPermissionTest, earlierUnknownFailureTest, settlementWinsObservationTest | 部分覆盖：策略真实性、来源/模式有效性为前提 |
| R12 | S12 | G01/G02; capturedIntentTest, providerGenerationTest, dedupSameDomainTest | 部分覆盖：兼容/资源身份声明为前提 |
| R13 | S13 | G06; historicalBranchTest, unstableNotRetrofittedTest | 部分覆盖：历史以不可变边界/前缀事实表示 |
| R14 | S14 | externalControllerGateTest, controllerReplacementTest; G02 | 部分覆盖：真实投影与外部控制器持久化未实现 |
| R15 | S15 | UI/写入独立 | 部分覆盖：角色资格有抽象，实际逐节点部署未验证 |
| R16 | S16 | authorizationBeforeReceiptTest, operationPermissionsTest | 部分覆盖：inspect/export/resource-use 后来加入抽象；真实认证待验证 |
| R17 | S17 | readyImportTest, finishedImportTest, historicalBranchTest | 部分覆盖：import回执加入，实际兼容/数据验证未执行 |
| R18 | S18 | importRejectionsTest：仅类型分类 | 部分覆盖：ETF字节/原子安全/decoder预算只归运行时 |
| R19 | S19 | 暂停/授权的两种提交顺序；suspendedSettleTest; G05 | 部分覆盖：真实持久化/监督为前提 |

<a id="indexed-scenarios-17"></a>

## 初期场景映射（17项，历史）

| ID | 状态 | 可执行证据 | 剩余范围/解释 |
| --- | --- | --- | --- |
| S1 | 部分覆盖 | fullSystemTest; G07 | 无实际 Agent依赖/API 检查；整数状态不区分业务操作 |
| S2 | 部分覆盖 | G04/G05; 下方 FIFO/过时通知/finish/故障测试 | 键/envelope分离已加入；真实应用/facade载荷未验证 |
| S3 | 抽象内覆盖 | hostLossTest; G01/G02/G04 | 替代宿主消费同一结果；不声称真实远程运行时 |
| S4 | 部分覆盖 | 下方崩溃边界测试 | 授权/结果回执已建模；崩溃/持久化仍为前提 |
| S5 | 部分覆盖 | 下方生命周期竞态; readyImportTest/finishedImportTest | 版本/资源仅抽象分类 |
| S6 | 部分覆盖 | 共享通用状态无 Agent操作分支 | 旧阶段两种 Definition 尚未补齐；后续修复见末表，真实对象处理API仍未执行 |
| S9 | 部分覆盖 | providerUnavailableTest; providerGenerationTest | 无完整服务清理/重启图/层级Scope |
| S10 | 部分覆盖 | authorityUnavailableTest | quorum成员/少数派分区/磁盘丢失为前提 |
| S11 | 部分覆盖 | G02/G03；下方恢复/裁定行 | 有界审计/envelope加入；注册模式/来源验证为前提 |
| S12 | 部分覆盖 | capturedIntentTest, providerGenerationTest, dedupSameDomainTest, dedupExpiryTest | 限于兼容/域/保护抽象 |
| S13 | 抽象内覆盖 | historicalBranchTest, unstableNotRetrofittedTest, failedHistoricalForkTest; G06 | 稳定资格不追溯产生，队列/ID新建 |
| S14 | 部分覆盖 | externalControllerGateTest, controllerReplacementTest, auditNoExecutionTest | 关卡/代次有模型；真实UI/投影/控制器存储未实现 |
| S15 | 待运行时验证 | uiIndependenceTest 覆盖一项抽象 | 无真实角色部署/native构建/Android生命周期/网络测试 |
| S16 | 部分覆盖 | authorizationBeforeReceiptTest, operationPermissionsTest | input/audit/settle/repeat权限区分；query/export/resource后来补齐抽象 |
| S17 | 部分覆盖 | readyImportTest, finishedImportTest, historicalBranchTest, importRejectionsTest | waiting/ready/finished激活和回执有模型，真实归档字节未验证 |
| S18 | 待运行时验证 | importRejectionsTest 仅拒绝分类 | 无真实ETF encoder/decoder或安全/资源测量 |
| S19 | 抽象内覆盖 | admissionBeforeSuspendTest, suspendBeforeAdmissionTest, unknownWhileSuspendedTest, suspendedSettleTest | 旧授权晚进入，新工作受封闭，恢复后消费 |

<a id="every-assertionerror-matrix-row-88"></a>

## 全部源断言/错误矩阵（88行，历史抽象）

保留原源触发条件、行ID与测试标识。覆盖状态不表示当前运行时实现，也不补全组合界限。非矩阵记录/接口表是上下文，不新增通过计数。

<a id="authority-and-recovery-errors"></a>

### authority-and-recovery-errors

来源：[authority-and-recovery.md](../architecture/authority-and-recovery.md)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| authority-and-recovery-errors.M01 | 状态提案来自过期纪元或修订号 | 抽象内覆盖 | faultTakeoverFirstTest; obsoleteEvaluatedUnknownTest | 状态/宿主/队首权限隔离 |
| authority-and-recovery-errors.M02 | 暂停或进入终态后请求执行授权 | 抽象内覆盖 | suspendBeforeAdmissionTest; G05 | 生命周期封闭新授权 |
| authority-and-recovery-errors.M03 | 缺少已提交意图，执行尝试令牌未知，或执行主体 / 绑定不匹配 | 部分覆盖 | replacementOwnerTest; G02 | 原绑定与观测载荷验证仍为抽象 |
| authority-and-recovery-errors.M04 | 已有 admitted Attempt，或授权提案的 execution_revision 过期 | 抽象内覆盖 | competingControllersTest | 执行修订独立，排除并行 admitted |
| authority-and-recovery-errors.M05 | 同一命令键对应不同载荷 | 抽象内覆盖 | admissionReceiptFirstTest; originalBindingEnvelopeTest; controlAndHostReceiptsTest (protocol_test) | 原 envelope 冲突先于当前条件 |
| authority-and-recovery-errors.M06 | 重复终局观测 | 抽象内覆盖 | observationIdIndependentTest (protocol_test); G03 | 稳定 ID 与载荷冲突分开，模式仍为前提 |
| authority-and-recovery-errors.M07 | 迟到观测与已有结果冲突 | 抽象内覆盖 | settlementWinsObservationTest | 保留迟到冲突，不覆盖结果 |
| authority-and-recovery-errors.M08 | 新的终局裁定或重复执行决策针对已终局调用 | 抽象内覆盖 | settlementPayloadRetentionTest (protocol_test) | 新决策先检查旧修订，再判断已解决 |
| authority-and-recovery-errors.M09 | 裁定类型、证据、结果或来源无效 | 部分覆盖 | boundedResolutionProvenanceTest (protocol_test) | 有界来源/证据/数据；真实审计模式未执行 |
| authority-and-recovery-errors.M10 | 发送前没有可用权威访问路径 | 抽象内覆盖 | authorityUnavailableTest | 无新写入/回执，旧授权仍可进入 |
| authority-and-recovery-errors.M11 | 提交响应丢失，或修改请求提交超时 | 部分覆盖 | receiptAfterControlTest | 只覆盖输入响应丢失 |
| authority-and-recovery-errors.M12 | 重试会改变去重域，或去重保护已经过期 | 抽象内覆盖 | dedupChangedDomainTest; dedupExpiryTest | 检查去重域/保护适用性 |
| authority-and-recovery-errors.M13 | 外部工作完成后，结果无法验证或记录 | 部分覆盖 | authorityUnavailableTest | 覆盖记录不可用，未展开无效/超大观测 |

<a id="s4"></a>

### S4

来源：[authority-and-recovery.md](../architecture/authority-and-recovery.md#s4)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| S4.M01 | 两个控制器使用同一 execution_revision 请求授权 | 抽象内覆盖 | competingControllersTest; G02 | 至多一项 admitted，预期执行修订独立 |
| S4.M02 | 同一 Attempt 被重复投递给同一执行主体 | 抽象内覆盖 | duplicateDispatchTest; G02 | 每个原主体/Attempt 至多一次本地进入 |
| S4.M03 | 工作进程在调用前或调用后退出，无法确认具体位置 | 抽象内覆盖 | replacementOwnerTest; unknownPrefix; G02/G03 | 调用前/进入后断连均保留，不转移授权 |
| S4.M04 | 授权回执丢失，随后 Run 暂停或宿主接管 | 抽象内覆盖 | admissionReceiptFirstTest; originalBindingEnvelopeTest (protocol_test) | 原回执跨暂停/接管/provider变化有效 |
| S4.M05 | 结果回执丢失或通知丢失 | 部分覆盖 | observationIdIndependentTest; unknownObservationIdsTest (protocol_test); hostLossTest | 稳定键/回执已建模，实际运输修复未执行 |

<a id="s11"></a>

### S11

来源：[authority-and-recovery.md](../architecture/authority-and-recovery.md#s11)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| S11.M01 | 旧 Attempt 为 unknown，新 Attempt 报告 failed 或 not_executed | 抽象内覆盖 | earlierUnknownFailureTest; earlierUnknownPrecheckTest; G03 | 旧 Lost 证据跨恢复失败/非执行保留 |
| S11.M02 | unknown 下追加审计证据 | 部分覆盖 | auditNoExecutionTest; boundedResolutionProvenanceTest (protocol_test) | 有界来源/审计证据；注册模式验证未执行 |
| S11.M03 | suspended / open Run 对 unknown 显式 settle | 抽象内覆盖 | suspendedSettleTest; G03/G05 | 唯一结果/回复，暂停时不提交业务 |
| S11.M04 | 一次 allow_repeat 后，两个控制器请求新 Attempt | 抽象内覆盖 | recoveryPermissionTest; repeatNotPermanentTest; 负控 oneUsePermitTest | 许可一次消费、token不变，拒绝竞争修订 |
| S11.M05 | 终局观测与 settle 竞争 | 抽象内覆盖 | observationWinsSettlementTest; settlementWinsObservationTest | 两种提交顺序，保留冲突来源 |
| S11.M06 | 已终局 / consumed 调用收到新的 settle 或 allow_repeat | 抽象内覆盖 | settlementPayloadRetentionTest (protocol_test) | 同时检查 stale_permission 与新修订 already_resolved |

<a id="boundaries-errors"></a>

### boundaries-errors

来源：[boundaries.md](../architecture/boundaries.md)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| boundaries-errors.M01 | Agent 定义导入 Effect / Durable 记录 | 待运行时验证 | 仅 G07 模型依赖图 | 须检查实际 imports/API |
| boundaries-errors.M02 | 外部输入提供任意模块、函数或更新回调 | 待运行时验证 | 封闭变体排除回调 | 须实现可信注册代码/数据边界 |
| boundaries-errors.M03 | 持久化状态包含运行时句柄或闭包 | 待运行时验证 | 仅可移植 ID/类型 | 须实际递归验证数据 |
| boundaries-errors.M04 | Effect 执行器导入 Durable 以记录结果 | 待运行时验证 | 仅 G07 模型依赖图 | 须检查真实 Effect→Durable 依赖 |
| boundaries-errors.M05 | 缺少已注册且兼容的定义或提供者 | 部分覆盖 | providerUnavailableTest; importRejectionsTest | 兼容谓词是前提 |
| boundaries-errors.M06 | 新建实体进程或应用仅用于组织代码 | 待运行时验证 | 无产品进程模型 | 须检查真实 OTP 进程/应用职责 |

<a id="capability-composition-errors"></a>

### capability-composition-errors

来源：[capability-composition.md](../architecture/capability-composition.md)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| capability-composition-errors.M01 | 依赖或提供者不可用 | 抽象内覆盖 | providerUnavailableTest | 无绑定，不伪造结果 |
| capability-composition-errors.M02 | 名称相同，但契约、模式或资源不兼容 | 部分覆盖 | providerUnavailableTest | 语义/资源匹配只为谓词 |
| capability-composition-errors.M03 | 授权后提供者代次改变 | 抽象内覆盖 | providerGenerationTest | 进入前本地拒绝 |
| capability-composition-errors.M04 | 重复分发或执行主体被替换 | 抽象内覆盖 | duplicateDispatchTest; replacementOwnerTest | 记录原主体/Attempt 的进入 |
| capability-composition-errors.M05 | 创建后 Scope 设置改变 | 抽象内覆盖 | capturedIntentTest; G01 | 保留创建时捕获配置 |
| capability-composition-errors.M06 | 重试选择新的去重域 | 抽象内覆盖 | dedupChangedDomainTest | 显式 repeat 可独立允许变更去重域 |
| capability-composition-errors.M07 | 安装外部控制器，但自动路径可以绕过 | 抽象内覆盖 | externalControllerGateTest; G02 | 外部路径不能被自动路径绕过 |
| capability-composition-errors.M08 | 归档或配置提供任意可执行回调 | 待运行时验证 | 封闭变体排除回调 | 须实际可信代码/ETF 边界 |
| capability-composition-errors.M09 | 将 Scope 描述为恶意代码沙箱 | 待运行时验证 | 可信成员前提 | 未建立 Scope 沙箱/安全保证 |

<a id="s12"></a>

### S12

来源：[capability-composition.md](../architecture/capability-composition.md#s12)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| S12.M01 | 已授权绑定的提供者代次改变，原主体尚未调用 | 抽象内覆盖 | providerGenerationTest | 原 Attempt 为 not_executed，不换绑定进入 |
| S12.M02 | 旧主体状态未知，新主体完成预检 | 抽象内覆盖 | earlierUnknownPrecheckTest | 新预检不清除旧 Lost |
| S12.M03 | 同一 Effect 在相同有效去重域内创建恢复 Attempt | 抽象内覆盖 | dedupSameDomainTest; dedupChangedDomainTest; dedupExpiryTest | 新主体/Attempt，Effect token不变；真实去重为前提 |

<a id="computation-and-effects-errors"></a>

### computation-and-effects-errors

来源：[computation-and-effects.md](../architecture/computation-and-effects.md)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| computation-and-effects-errors.M01 | 状态、输入、参数或结果无效 / 不可移植 | 待运行时验证 | 仅 ImportCheck 分类 | 须真实载荷/结果递归可移植验证 |
| computation-and-effects-errors.M02 | 代码或模式未注册 / 不兼容 | 部分覆盖 | importRejectionsTest | 代码/模式注册仅为分类 |
| computation-and-effects-errors.M03 | 同一命令键或输入键对应的数据改变 | 抽象内覆盖 | inputIdIndependentTest; observationIdIndependentTest (protocol_test) | command/input/observation 表独立 |
| computation-and-effects-errors.M04 | 旧修订号或旧所有权权限 | 抽象内覆盖 | faultTakeoverFirstTest; controllerReplacementTest | 宿主/控制器/执行权限分别隔离 |
| computation-and-effects-errors.M05 | 缺少必需资源 | 部分覆盖 | providerUnavailableTest | 资源谓词不验证资源内部 |
| computation-and-effects-errors.M06 | 提交前没有有效权威访问路径 | 抽象内覆盖 | authorityUnavailableTest | 写接口 guard |
| computation-and-effects-errors.M07 | 已提交修改请求，但无法确定提交结果 | 部分覆盖 | receiptAfterControlTest | 仅输入不确定确认 |
| computation-and-effects-errors.M08 | 边界不稳定 | 抽象内覆盖 | unstableNotRetrofittedTest | 资格在边界提交时记录 |
| computation-and-effects-errors.M09 | 存在未决 Effect 或未处理回复时结束 | 抽象内覆盖 | invalidFinishTest | 拒绝部分步骤，FailRun单独提交 |
| computation-and-effects-errors.M10 | 定义已确认异常、非法返回或超过步骤预算 | 部分覆盖 | failedLateResultTest | 故障分类/资源预算被合并 |
| computation-and-effects-errors.M11 | 向已结束 Run 提交输入或请求恢复 | 抽象内覆盖 | finishFirstInputTest; finishedImportTest | 终态拒绝输入/resume |

<a id="s2"></a>

### S2

来源：[computation-and-effects.md](../architecture/computation-and-effects.md#s2)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| S2.M01 | ready 的后续推进后，已有外部输入和两条回复；不同来源交错入队 | 抽象内覆盖 | twoEffectFifoTest; G04 | 两个 Effect 共享 FIFO，Continuation 排队尾 |
| S2.M02 | 外部输入改变状态，使队列中的旧后续推进过期 | 抽象内覆盖 | fifoContinuationTest; G04 | 旧 Continuation 只改游标/历史 |
| S2.M03 | unknown 通知先提交，终局回复在该通知消费前提交 | 抽象内覆盖 | recoveryPermissionTest; obsoleteEvaluatedUnknownTest | 终局消费前处置过时通知 |
| S2.M04 | 宿主对 unknown 通知求值后，终局结果先于步骤 / 故障提交 | 抽象内覆盖 | obsoleteEvaluatedUnknownTest; obsoleteUnknownFaultTest | 求值后的业务/故障旧提案都被隔离 |
| S2.M05 | 最后一条终局回复的消费步骤返回 finish | 抽象内覆盖 | finishLastReplyTest; G05 | 结果/最后消费/生命周期原子提交 |
| S2.M06 | 存在 pending / executing / unknown Effect 时返回 finish | 抽象内覆盖 | invalidFinishTest; G05 | 整项非法步骤拒绝，条件 FailRun 保留工作 |
| S2.M07 | step 异常、非法返回或超过步骤预算 | 部分覆盖 | invalidFinishTest; failedLateResultTest | 故障合并为 FaultStep；真实异常/堆/时间待实现 |
| S2.M08 | failed 后，先前已授权工作报告结果 | 抽象内覆盖 | failedLateResultTest; G03/G05 | 保留晚结果/未处理回复，不产生 consumed |

<a id="lifecycle-and-archives-errors"></a>

### lifecycle-and-archives-errors

来源：[lifecycle-and-archives.md](../architecture/lifecycle-and-archives.md)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| lifecycle-and-archives-errors.M01 | 暂停命令与执行授权竞态 | 抽象内覆盖 | 两种 admission/suspend 顺序测试 | 原子串行命令粒度是前提 |
| lifecycle-and-archives-errors.M02 | 分支边界为 failed 快照，或存在未处理完毕的 Effect / 完成结果 | 抽象内覆盖 | unstableNotRetrofittedTest; failedHistoricalForkTest | 只能用已记录稳定前缀 |
| lifecycle-and-archives-errors.M03 | 对 finished / failed Run 请求恢复 | 抽象内覆盖 | finishedImportTest; failedLateResultTest | 保留终态生命周期 |
| lifecycle-and-archives-errors.M04 | 缺少源历史前缀或检查点数据 | 部分覆盖 | importRejectionsTest | 缺失数据仅分类，无真实归档 |
| lifecycle-and-archives-errors.M05 | 格式、数据配置、模式或代码不受支持 | 部分覆盖 | importRejectionsTest | 版本仅分类，无代码加载/注册实现 |
| lifecycle-and-archives-errors.M06 | 目标资源或权限不满足要求 | 部分覆盖 | importRejectionsTest | 资源/权限仅分类，完整接入策略未展开 |
| lifecycle-and-archives-errors.M07 | 不可移植项、格式错误或尾随字节 | 待运行时验证 | BadData 分类 | 须真实 ETF 句柄/畸形/尾随测试 |
| lifecycle-and-archives-errors.M08 | 数据过大、结构过深、项过多，或超出解码器资源限制 | 待运行时验证 | ExcessiveData 分类 | 须测量字节/深度/项数/时间/堆界限 |
| lifecycle-and-archives-errors.M09 | 未知原子需要创建，或需要安装代码 | 待运行时验证 | 不含代码的封闭模型 | 须拒绝新原子/代码安装 |
| lifecycle-and-archives-errors.M10 | 数据配置不允许压缩或 instance-local 包装 | 待运行时验证 | 无编码字节 | 须拒绝压缩与 instance-local |
| lifecycle-and-archives-errors.M11 | 已有导入键对应的逻辑归档或绑定改变 | 部分覆盖 | forkAndImportReceiptsTest (protocol_test) | envelope 冲突已建模，真实逻辑归档/绑定/前缀载荷未验证 |

<a id="s5"></a>

### S5

来源：[lifecycle-and-archives.md](../architecture/lifecycle-and-archives.md#s5)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| S5.M01 | finish 与新输入提交竞争 | 抽象内覆盖 | finishInputFirstTest; finishFirstInputTest | 两种顺序均保留已接受输入或拒绝新输入 |
| S5.M02 | 定义故障与宿主接管竞争 | 抽象内覆盖 | faultTakeoverFirstTest; faultBeforeTakeoverTest | 接管后旧宿主不能条件 FailRun |
| S5.M03 | finished / failed Run 请求 resume | 抽象内覆盖 | finishedImportTest; failedLateResultTest; G05 | 保留终态结果/生命周期，不重启 |
| S5.M04 | failed Run 仍有已授权工作 | 抽象内覆盖 | failedLateResultTest; failedHistoricalForkTest | 保留晚观测，较早稳定边界仍可派生 |

<a id="s19"></a>

### S19

来源：[lifecycle-and-archives.md](../architecture/lifecycle-and-archives.md#s19)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| S19.M01 | Suspend 先于 AdmitAttempt | 抽象内覆盖 | suspendBeforeAdmissionTest | 暂停后无新授权 |
| S19.M02 | AdmitAttempt 先于 Suspend，原主体稍后才调用 | 抽象内覆盖 | admissionBeforeSuspendTest | 旧授权暂停后仍首次进入/记录 |
| S19.M03 | Suspend 后原主体消失，新主体试图继承授权 | 抽象内覆盖 | unknownWhileSuspendedTest; replacementOwnerTest | 保留 Lost，不继承或新增授权 |
| S19.M04 | 暂停期间终局结果到达或 settle 提交 | 抽象内覆盖 | admissionBeforeSuspendTest; suspendedSettleTest | 结果/回复原子保存，恢复后 FIFO 消费一次 |

<a id="platforms-and-trust-errors"></a>

### platforms-and-trust-errors

来源：[platforms-and-trust.md](../architecture/platforms-and-trust.md)。

| 行ID | 源触发条件 | 状态 | 断言/测试 | 剩余证据与解释 |
| --- | --- | --- | --- | --- |
| platforms-and-trust-errors.M01 | 未知或未授权客户端，或未获授权的 Run 操作 | 部分覆盖 | authorizationBeforeReceiptTest; operationPermissionsTest | inspect/export/resource-use 接入仍未实现 |
| platforms-and-trust-errors.M02 | 无效模式、任意 MFA / 模块、不安全项 | 待运行时验证 | 仅类型化可移植模型 | 须真实 MFA/不安全项验证 |
| platforms-and-trust-errors.M03 | 未安装兼容计算定义或提供者 | 部分覆盖 | providerUnavailableTest; importRejectionsTest | 注册/兼容仍为前提 |
| platforms-and-trust-errors.M04 | 视图或终端连接中断 | 抽象内覆盖 | uiIndependenceTest | 抽象 UI 断连保留状态/历史 |
| platforms-and-trust-errors.M05 | 计算或执行宿主消失 | 部分覆盖 | hostLossTest; replacementOwnerTest | 真实监督与节点故障未执行 |
| platforms-and-trust-errors.M06 | 权威写入不可用 | 抽象内覆盖 | authorityUnavailableTest | 不可用写路径不发虚假持久确认 |
| platforms-and-trust-errors.M07 | 使用缓存投影授予所有权或执行权限 | 待运行时验证 | 单一致性权威前提 | 须真实缓存读拒绝/一致性查询 |
| platforms-and-trust-errors.M08 | 将不可信节点作为普通成员 | 待运行时验证 | 可信成员前提 | 排除恶意/第三方普通成员 |

<a id="supporting-p01p22-index"></a>

## P01–P22补充索引（历史）

| 条款 | 全局/断言证据 | 范围与剩余义务 |
| --- | --- | --- |
| P01 | G04/reference; precommitLossTest, invalidFinishTest | 模型内 CommitStep 原子性 |
| P02 | G02/G04; host/controller/revision竞态 | 多个独立权限维度隔离 |
| P03 | G01; authorizationBeforeReceiptTest, receiptAfterControlTest | 模型命令回执加入，真实 query授权未执行 |
| P04 | G02; duplicateDispatchTest, competingControllersTest | 重复分发/竞争授权有检测 |
| P05 | G02/G03; replacementOwnerTest, unknownWhileSuspendedTest; recoveryOwnerReuseGapTest | 旧授权不转移；旧阶段恢复可复用未知主体，后来已修复 |
| P06 | G01/G02; capturedIntentTest, providerGenerationTest | 在兼容前提下覆盖捕获 |
| P07 | G02授权知识; dedupSameDomainTest/ChangedDomainTest/ExpiryTest | 在声明策略/保护前提下覆盖去重域 |
| P08 | G03; earlierUnknownFailureTest, earlierUnknownPrecheckTest | 保留较早未知 |
| P09 | G03/reference; 两种settlement顺序, duplicateObservationTest | 抽象内结果/回复/载荷与观测键冲突 |
| P10 | G02/G03; repeatNotPermanentTest, settlement竞态 | 一次许可/顺序/回执/有界来源；注册模式为前提 |
| P11 | G02/G04/G05; control/host/controller竞态 | 控制/宿主/控制器竞态 |
| P12 | G04/reference; twoEffectFifoTest, fifoContinuationTest | FIFO与过时输入 |
| P13 | G04/reference; obsoleteEvaluatedUnknownTest, obsoleteUnknownFaultTest | 旧unknown提案隔离 |
| P14 | G05; unknownNotificationConsumptionTest, finishLastReplyTest | 通知与最后回复消费 |
| P15 | G05; failedLateResultTest, invalidFinishTest | 终态协议有覆盖，真实故障分类/预算未执行 |
| P16 | G06/reference; unstableNotRetrofittedTest | 提交时稳定资格 |
| P17 | G06; readyImportTest/finishedImportTest/historicalBranchTest | 模型边界快照与本地身份 |
| P18 | importRejectionsTest | 仅拒绝类别，无真实validators |
| P19 | G01/G02; authorityUnavailableTest | 串行持久权威为前提 |
| P20 | G02; providerUnavailableTest, externalControllerGateTest | 授权关卡有覆盖，完整Scope资源图未展开 |
| P21 | G03/G04; duplicateUnknownTest/duplicateObservationTest; observationBindingConflictCounterexampleTest | 旧阶段观察键漏原绑定/意图，后来已修复 |
| P22 | uiIndependenceTest; 不可变权威状态 | 旧阶段无角色部署模型，后来增加角色抽象，真实部署仍未验证 |

<a id="boundaries-and-assumptions"></a>

## 组合边界与前提

| 边界 | 模型内检查的提供方保证 | 使用方 | 实现前提/剩余范围 |
| --- | --- | --- | --- |
| Gateway→authority | input授权先于回执读取，无写入不发新确认 | inbox/host | 命令envelope有模型，真实接入未实现 |
| Host→authority | evaluation无进入，commit原子保存input/state/intent | controller/execution | 注册纯Definition与真实故障/预算观测 |
| Authority→owner | owner/provider/generation/domain/token不可变，至多一admitted | provider本地进入 | 线性化持久权威与可信实例身份 |
| Provider→observation | 进入计数/绑定记录、有效结果分类 | outcome/reply | 回复模式、真实失败声明与去重保护 |
| Outcome→FIFO | 一个权威结果/终局输入，unknown独立 | 业务消费/finish | 稳定观测键，真实传输修复未完成 |
| Lifecycle→controller/host | 新提案隔离，旧授权/观测保留 | 恢复/晚结果 | 真实监督与磁盘持久化 |
| 稳定边界→分支 | 提交时资格/前缀、新suspended队列/身份 | 分支新工作 | 真实归档/注册/资源验证 |
| Foundation→application | 封闭可移植输入、无环模型依赖 | 通用计算 | 实际领域Definition与依赖/API检查 |

回执不是新进入许可；授权与进入单独记录。晚完成不把旧不稳定边界追溯变稳定。typed有效类别是接口前提，不是ETF/安全证明；G07只检查模型图，不检查不存在的产品import。

<a id="current-fidelity-checkpoint-scenario-references"></a>

## 后续保真检查点的对应修复

| 义务 | 最终详细模型可执行证据 | 仍未建立 |
| --- | --- | --- |
| P03/S4回执与集成 | combinedInterleavingTest（41个真实envelope转换）、recoveryFixtureEnvelopeTest、conditionalSchedulerEnvelopeTest | 该最终源的新抽样/BMC |
| P09/P21观测键 | observationBindingConflictCounterexampleTest 要求key_conflict；observationIdIndependentTest | 真实模式/来源信任 |
| P04/S4/S11恢复主体 | recoveryOwnerReuseGapTest 重连后拒绝旧实例；recoveryOwnerMutationTest | 可信实例分配实现 |
| P08/P09失败声明 | inconclusiveFailureTest、failureDeclarationMutationTest、terminalThenLaterUnknownTest | 真实注册声明正确性 |
| S5/S13/S17控制/派生 | terminalResumeBlindSpotTest 检测变异；fabricatedBoundaryMutationTest；deterministicFirstDefinitionTest 包含完成载荷/事件历史 | 真实归档字节/注册表 |
| S1/S6定义/基础层 | deterministicFirstDefinitionTest、deterministicSecondDefinitionTest、deterministicDefinitionRefusalTest | 两种不透明注册例子，实际Agent/API依赖仍待实现 |
| S2创建/后续推进 | startReadyReceiptTest、CreationCommand | 默认Run0假设已创建 |
| S9/S12作用域/资源 | scopeHierarchyAndIsolationTest、resourceIdentityAndPermissionTest | 两层Scope，完整provider清理/依赖图未覆盖 |
| S15角色/写入 | roleWriteAndExecutionEligibilityTest | 聚合角色，真实节点放置/平台测试未执行 |
| S16查询/导出/资源 | queryExportResourceAuthorizationTest | 真实认证/安全接入 |
| 命令/历史独立性 | receiptHistoryMutationTest、reference receipt/history差量检查 | 原子线性化权威仍前提 |

旧gap probe后来转拒绝/检测回归，不能改写原历史坏行为日志的归属。最终97测试/九typecheck通过，无该最终详细模型新抽样/backend/compile；旧原始日志仅本地。原全文gate被用户核心范围取代，没有被算成通过；实际核心結果及其有限域、稀疏消费、depth10无结论与恢复调度界限见[核心报告](core/verification-report.md)。Ra仍是条件候选，Mnesia/disk_log只是既有比较，没有新增依赖或运行时。
