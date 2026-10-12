# 正常使用模型补全

状态: 已完成正常闭环的最小抽象与初步覆盖验收, 实际检查记录见下文. 补全对应
[正常使用审查](normal-use-audit.md) 提出的四组缺口, 保留既有执行/命令/治理参考规格.
本页的整数身份、字段、策略与时钟都是模型选择, 不批准产品 API、SQL schema 或 codec.

## 范围与结构

[beamletNormalUse.qnt](beamletNormalUse.qnt) 是可执行入口, main 为 `normalUseAnalysis`.
默认 init/step/safety 分别代理 `normalInit` / `normalStep` / `normalSafety`.
`normal/` 按 state、logic、actions、properties 分层; `scenarios/normal/` 提供确定场景,
`mutations/normal.qnt` 提供专用故意错误规则. 正常入口不导入测试或 mutation.

正常入口复用同一份核心 Authority/Worker/外部资源账本, 并增加一组 `usage` 状态,
保存提交目录、Handler 快照、提交传输集合及独立观察. 五组变量、九个核心参数保留.
后续已切换到不含治理状态的独立执行核心; 本页下方运行记录保留第一轮检查点,
最新依赖/恢复组合、提前停止与原幂等窗口修正见 [执行核心覆盖](execution-core-coverage.md).
旧入口仍以已建立的 Open Intent 开始, 用于原来的执行与治理检查; 正常入口把它看作尚未激活的槽位,
只有提交已建立聚焦 Intent 后才能建立 Execution. 新测试不直接重置执行账本构造前缀.

提交目录最多两个 Intent, 每个稳定 `namespace + key` 定位不可变定义与上下文.
只有首个 Intent 的完整执行被展开; 第二个用于检验命名空间隔离、无 key 创建与身份不混淆,
不声称已建模两个 Intent 的执行调度或 SQL 并发. 独立 Intent 的并发仍是后端符合性验证边界.

## SPEC 到抽象和检查的映射

| 要求 | 最小抽象 | 主要场景 / 性质 |
| --- | --- | --- |
| Q4/Q41/Q42 稳定提交身份与不可变定义 | SubmissionIdentity、Definition、原子目录查找/创建; 同 key 比较原定义 | stableSubmissionReplayTest、concurrentDefinitionFirstWinsTest、concurrentDefinitionReverseWinsTest、submissionIdentitySound |
| 定义包括兼容 Operation、输入、硬约束与初始策略 | opaque 整数与类型化 RetryPolicy, 结构相等 | conflictingDefinitionTest、operationVersionConflictTest、hardConstraintConflictTest |
| namespace 隔离; 无 key 是新操作 | 两项目录, 上下文与 key 分开 | namespaceSeparatesIdentityTest、unkeyedAlwaysCreatesTest |
| Closed 可读取并复用原业务结果 | Report/Outcome 增加 opaque value; ExistingIntent 返回当前已保存 Outcome | closedSubmissionReturnsBusinessValueTest、outcomeValuesEvidenced、factReadsSound |
| 同报告身份不同业务值保留冲突 | 完整报告相等与身份相等分开; 同尝试矛盾确定值设置 conflict | lateDifferentSuccessValuePreservedTest; 原始证据保留、Outcome 不变 |
| Q14/Q45 不依赖常驻 Worker 的回调型 Pending | Start Authorization 同步保存 CallbackBinding; 独立受信入口形成 ByCallback Report | releasedWorkerCallbackWithoutQueryTest、callbackCorrelationBeforeInvocationTest、handlerLaunchesSound |
| 回调乱序、过期 lease、进程释放与 Coordinator 重启 | 发出、完成、入账仍是不同动作; Worker 局部状态清空不清除关联 | completionBeforePendingCallbackTest、expiredLeaseCallbackTest、callbackDuplicateAndRebootTest |
| 验证回调来源与关联 | verified 受信入口输入, 相关 ID 匹配持久绑定; 与资源实际结果一致 | callbackRejectionTest、wrongCallbackCorrelationDisabledTest |
| Q36/Q39/Q43 Handler 兼容及条件快照 | operation 表示含契约版本的身份; id 表示实现; protocol 表示外部键/作用域解释 | incompatibleHandlerDisabledTest、compatibleHandlerReleaseAllowedTest、handlerSnapshotSurvivesRestartTest |
| 未声明能力不可使用 | Pending、query 通过启动时快照守卫 | unsupportedPendingDisabledTest、unsupportedPendingReceiveDisabledTest、unsupportedQueryDisabledTest、queryCapabilityCompletesWithoutWorkerTest |
| Q44 稳定幂等上下文及条件重验 | Intent context; 已核验的幂等窗口; 新尝试保留定义/上下文/协议 | validIdempotentRetryUsesOriginalContextTest、expiredIdempotencyDoesNotPermitRetryTest、retryContractsSound |
| 条件不能由能力名称替代 | 有效期、同输入/上下文、同外部协议, 在替代/新授权/调用时检查 | noIdempotencyDoesNotPermitRetryTest、retryCannotChangeExternalProtocolTest、retryCannotDropIdempotencyTest、expiredBeforeInvocationDoesNotCallTest |
| Q8/Q24/Q29 明确停止策略与合格失败原子接受 | StopOnFailure / RetryOnce 两个示例策略; report + Execution + Outcome/Closed/History 原子更新 | failedCompletionAtomicTest、retryPolicyKeepsFirstFailureOpenTest、retryExhaustedFailureAtomicTest、normalAcceptanceAtomic |
| 不确定性不因预算耗尽变失败 | 沿用 noUnresolvedRisk、旧成功/冲突阻塞, 策略不绕过 canCommit | unknownBudgetDoesNotCreateFailureTest、原有 unknownFailure / oldSuccessFailure 反例 |
| Q15/Q34 重启后发现工作与事实读取 | 一致持久快照读取; 从 Prepared/Waiting/Unknown 当前尝试发现候选, 不授予许可 | unknownFactsReadableAfterRestartTest、preparedWorkRediscoveredTest、factReadsSound |

`normalSafety` 合取独立执行 `safety` 与提交身份、Handler/实际调用、重试契约、原子接受和读取性质.
后续增加停止见证和原幂等窗口的独立回查; 第一轮组合账本的 commandSafety 仍由原组合入口检查.
检查实际记录与独立前后快照; 不能只用一个“已合格”标志代替检查.
停止决定还从原定义策略和尝试数量独立重算; 故意伪造 stop=false 也不能掩盖漏终结.
新增回调/取消竞争场景覆盖先取消保留迟到证据、先完成后取消禁用, 正常随机 profile 仍不主动取消.
所有原场景的默认值为 0; 正常入口用 1/2 区分业务/错误内容, 9 用于制造错误结果反例.
这些数值只承载相等关系, 不代表数值编码或业务含义.

## 原子粒度与可信前提

- 提交请求与处理分开, 可以在确认丢失后重投或发生相同身份不同定义的竞争.
  目录查找与首次建立为一个原子 Authority 步骤, 不模拟 SQL 的唯一索引或隔离级别.
  相同提交身份复用当前 Intent/Outcome, 与“协调命令返回原处理结果”是不同协议.
- 回调关联在 Start Authorization 提交时建立, 先于外部调用, 不等 Pending 报告.
  correlation 是 opaque ID, 不充当认证凭证. `verified=true` 抽象 Adapter 已核验来源/内容;
  模型检验未核验或关联错误不得入域, 不证明真实验签、重放防护和第三方重投.
- Worker 释放复用原崩溃动作清空易失状态, 而不是等待其常驻. 外部完成、回调发出和接收仍能独立发生.
  能力支持查询的路径与纯回调路径各自验证, 不用查询替代纯回调覆盖.
- Handler 数据代表 Authority 已核验的契约事实, 不是客户端任意声明.
  `protocol` 相等抽象外部键与作用域解释一致; `validThrough` 是可信资源协议保证的窗口.
  `usage.contractTime` 表达该保证的抽象不可回退时间, 与可能回拨的 Authority lease 时钟分开;
  `normalClock` 同时前进资源时间, 回拨 lease 时钟不能延长窗口.
  `clockRollbackDoesNotRenewIdempotencyTest` 检查这条边界. 正常 profile 不引入时钟故障;
  时钟边界由定向场景检查.
- 依赖幂等的后续调用在资源契约有效时才允许. 这是合规 Handler/资源契约的抽象前提,
  不等同于调用前重新检查 Authority lease, 不证明真实网络延迟下的时间裕量或资源原子去重.
  两次调用仍可记为两次 effects; 本模型不宣称外部 exactly-once.
- StopOnFailure 表示已决定不再尝试; RetryOnce 在两个已建立尝试后停止.
  它们覆盖停止/继续的正常选择, 不批准生产预算、退避或错误分类算法.
  Unknown、冲突、旧成功未解释仍阻止普通失败; 不能因策略选择停止就绕过证据守卫.
- 核心原语继续支持“先保存失败事实, 后由策略终结”; 正常入口额外表达接收时已具备停止依据的同事务终结.
  两者表示不同处理上下文, 不把所有失败报告一律立即终结.
- readFacts 是模型中的一致快照读取, discoverWork 是候选投影. 不模拟分页、索引、调度公平性、唤醒通知或真实 API 权限.
  通知不是候选的唯一来源, 发现候选不等同于合法领取或启动.

## 可执行 profile 与复现

`normalStep` 不包含主动取消、故障、丢包和治理动作, 避免原 step 的早取消掩盖正常路径.
正常 profile 包含提交重投、同步/回调/查询完成、读取与发现; 终态仍允许真实读取,
没有给 Open 增加 blanket stutter. 定向前缀由真实动作生成:

- `normalInit`: 尚无提交或启动, 检查完整前半段.
- `callbackRunningInit`: 已提交/授权/调用, 检查独立完成与乱序后半段.
- `callbackReleasedInit`: Pending 已保存且 Worker 已释放, query 不支持.
- `retryPendingInit`: RetryOnce 首次已知失败保持 Open, 仅有合格幂等条件才能替代.

前缀初始已经成立的 witness 不计作本轮新事件覆盖. `normalStep` 仍使用非确定调度,
可达的正常终结不等于所有调度最终终结. 回调、释放完成、条件重试与原子失败分别有见证和确定场景.

```sh
mix beamlet.check --phase typecheck --jobs 4 --threads 4
mix beamlet.check --phase test --jobs 4 --threads 4
mix beamlet.check --jobs 4 --threads 4 --log-dir /tmp/beamlet-normal-completion-full
quint run model/quint/beamletNormalUse.qnt --main normalUseAnalysis --invariant safety \
  --max-samples 10000 --max-steps 100 --seed 123 --backend rust --n-threads 2 \
  --witnesses submittedWitness reusedWitness callbackWitness readWitness failureAtomicWitness \
  discoveryWitness succeededReached failedReached waitingReached
```

Mix 默认保留原 30 组 / 42,000 条, 新增四组正常前缀各 1,000 条, 共 34 组 / 46,000 条轨迹.
正常/类型/mutation 检查已接入相应 phase; 40 个新增正常场景与原 185 个分开统计, 合计 225 个.
新增七条 mutation 分别破坏结果正文、定义不变、回调关联、幂等有效期、成功原子性、上下文及失败原子性.
预期反例必须实际报告 Invariant violated 并生成非空 ITF, 解析/运行错误不算检出.

## 实际检查记录

- 完整检查日志: `/tmp/beamlet-normal-completion-full`, 13 个类型入口通过.
  新入口最终类型检查另见 `/tmp/beamlet-normal-final-checks-v2.log`.
- 原 185 个正常场景通过; 最新新增 40 个正常场景全部通过,
  日志 `/tmp/beamlet-normal-final-40-tests.log`. 不把工具测试计入 Quint 场景数.
- 34 组 / 46,000 条抽样已完成, max-steps=100、输入 seed=42、jobs=4、threads=4;
  未观察到相应运行所检查的 Safety 违规. 新入口使用 `--step normalStep`,
  init 分别为下表四个合法起点, 检查 `normalSafety`.
- 完整检查退出码为 0, 原六十条与新增七条 mutation 全部通过预期反例检查,
  67 份 ITF 均已解码, 核对原入口五组状态、新入口六组状态及实际违规输出.
  新增七条另逐一核对具体前后变化, 见 [反例记录](counterexamples.md).
- 81 个 Quint 文件均不超过 200 行, 导入无环且正常入口不导入测试/mutation;
  Mix 工具 10 个测试、格式检查与修改文档/Elixir 的主动诊断通过. Quint 使用实际 CLI, 无 Quint LSP.

下表每组 1,000 条轨迹, 各列可重叠. “—”表示目标在初始化已成立, 不算新的事件覆盖;
零命中按该 profile 的能力与策略解释, 不将不变量通过替代可达性.

| 正常入口 init | 回调发出 | Worker 释放后成功 | 条件重试 | 成功终结 | 失败原子终结 | 曾 Waiting |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| normalInit | 245 | 0 | 0 | 461 | 468 | 148 |
| callbackRunningInit | 1000 | 0 | 0 | 494 | 506 | 646 |
| callbackReleasedInit | 1000 | 460 | 0 | 460 | 540 | — |
| retryPendingInit | 0 | 0 | 1000 | 347 | 358 | 0 |

额外使用输入 seed=123、Rust / threads=2, 从默认正常 init/step 检查 safety,
完成 10,000 条、每条最多 100 步的抽样, 未观察到所检查不变量的违规; 日志
`/tmp/beamlet-normal-completion-final-10000.log`, 退出码为 0.
成功、失败原子终结、回调发出、曾 Waiting 分别命中 4,611 / 4,660 / 2,294 / 1,452 条;
提交、复用及事实读取各命中 10,000 条. 连同正式回归共 56,000 条已完成轨迹.
这组仍不主动释放 Worker 或提出 RetryOnce, 不将它当作相应路径覆盖.

所有起点均观察到读取和原定义提交复用; 提交本身只在 normalInit 下用于新提交覆盖.
normalInit 使用 StopOnFailure 且不释放 Worker, 因此其释放完成/重试为零;
callbackRunningInit 也不主动释放 Worker. callbackReleasedInit 已释放 Worker 但尚未完成,
其 460 条释放后成功来自新回调路径. retryPendingInit 的初始 Handler 不支持 Pending/回调,
所以相应列为零; 重试后成功/失败路径均实际到达. 计数不是事件数、成功率承诺或穷尽证明.

## 验证边界与后续

仍不覆盖真实 codec/值域预算、签名与权限协议、SQL/Ecto 并发/掉电、全局调度、跨 Intent 执行、
Authority 迁移、归档清理、Byzantine、外部 exactly-once 或公平性/Liveness 证明.
这些边界不阻止检查首版正常闭环的上述最小语义.
Q78 撤销专属授权仍未新增验证, 治理继续后置. 第一轮未执行依赖切割; 后续已完成核心独立,
见 [执行核心覆盖](execution-core-coverage.md). 尚无 Runtime 实现.

后续改动提交身份、Operation 兼容、回调关联、重试条件或失败接受时,
先更新相应纯逻辑/场景与正常 profile, 再改实现; 不以实现中的错误反向放宽规格.
构建期的参数/类型/禁用动作检查错误、限时终止及被后续版本替代的未完成抽样不计为通过或正常模型反例;
以上只统计已完成的正式回归与额外 seed 抽样. 这些结果是抽象场景与有界轨迹证据, 不是穷尽正确性证明.
