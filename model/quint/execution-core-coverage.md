# 执行核心隔离与恢复组合覆盖

状态: 已建立独立执行核心、迁移首版场景/反例、增加恢复组合和无处置投影对照. 最新实际检查记录见下文.
原组合参考模型保留; 本页不声称协调命令与治理内部已经进一步拆成独立账本.

## 1. 依赖与状态

- [beamletExecution.qnt](beamletExecution.qnt): 只组合执行动作/性质. Ledger 不含 revision、Decision、命令/拒绝缓存或规则/处置链;
  Message 只有启动、报告与回执; ExternalState 不含命令处理/规则退役观察.
- [beamletNormalUse.qnt](beamletNormalUse.qnt): 改为依赖上述核心, 增加提交、Handler 与正常接受/读取抽象.
- [beamletRecovery.qnt](beamletRecovery.qnt): 同一正常状态上组合 crash/restart、失效、双向 lease 时钟、重投/丢包与策略停止;
  不调用治理动作. `step` 在正常动作与恢复动作之间选择, 没有 Open 的兜底空转.
- [beamletCore.qnt](beamletCore.qnt): 保留完整组合参考, 继续验证协调/治理语义及与执行的交互.

共同的领域类型、常量/默认值、lease/报告与 Worker/资源纯计算分别由 `base/execution_*` 和
`logic/execution_{leases,reports,worker_values}` 单独拥有. 原组合逻辑使用共享纯更新, 再在适用路径更新 judgment revision.
普通证据解释与协调处置后的证据解释分别明确; 首版原始冲突阻塞终结, 未解释旧成功阻塞普通 Failed, Cancelled 独立.
共享 AuditKind 保留两个扩展历史标签以兼容参考记录, 不引入其决定、注册表、命令状态或解释规则.

两种账本保留各自 frame wiring 和 Outcome/替代资格, 因为参考模型还允许明确协调改变证据解释.
这增加了少量规格代码, 以共享纯规则、迁移场景和投影对照约束漂移; 不靠复制后各自通过就宣称语义等价.
Quint 参数仍在外层一次绑定, 每个场景共用单一未绑定 fixture.

`test/quint_structure_test.exs` 检查三个首版生产入口的传递导入: 不得依赖组合参考、测试/mutation 或治理类型;
同时检查全部 Quint 导入无环和每文件不超过 200 行. 生产入口不导入投影参照.

## 2. 场景和反例迁移账

| 原资产 | 现位置/入口 | 保留方式 |
| --- | --- | --- |
| strictTests 的 23 场景 | 原 `scenarios/strict` 和原模块名, fixture 改依赖 beamletExecution | 全部原 run 名称/断言保留; prefix 检查核心 safety |
| fencedTests 的 2 场景 | 原 `scenarios/fenced`, fixture 改依赖 beamletExecution | 可靠排除、旧调用禁用和替代保留 |
| repeatingTests 的 79 场景 | 原组合参考不动 | 执行/协调、命令原结果与版本等组合检查继续运行 |
| conflictTests 的 81 场景 | 原组合参考不动 | 冲突、取代、撤销/重投组合检查继续运行 |
| 原正常闭环 40 场景 | 原名称保留, normal state 改依赖独立核心 | 提交、回调、Handler、读取与原子接受继续检查 |
| 新增正常/恢复 9 场景 | `scenarios/normal/recovery_test.qnt`, 汇入 normalUseTests | 丢回调、丢授权回复、重启旧许可、提前停止/禁用、原窗口约束 |
| 新增 5 投影场景 | beamletExecution_test.qnt / executionProjectionTests | 初始、回调、重试、到期和冲突窗口 |
| 原执行 9 mutation + oldSuccessFailure | 原入口名/BUG 不变, 改依赖独立核心 | 唯一/不可变、失效、Unknown、旧成功等指定性质仍检出 |
| 原正常 7 mutation | 原入口名/BUG 保留, 改用独立核心 | 新快照字段随状态类型更新; 原错误仍检出 |
| 新增 normalExtendedIdempotencyWindow | 正常 mutation 第 8 条 | 独立检查旧窗口, 新 Handler 声明不能延长旧 key 保证 |
| 其余 50 mutation | 原组合参考不动 | 协调命令/冲突处置/规则/撤销的反例继续检查 |

当前正常场景合计 `23 + 2 + 79 + 81 + 49 + 5 = 239`; mutation 合计 68.
核心性质仍检查独立授权/提交/替代见证、回执持久性、证据与真实资源分离, 不删除见证缩小状态.

## 3. 无处置投影对照

测试专用 `scenarios/execution/projection_test.qnt` 将独立 Ledger 嵌入无决定/命令的原账本,
检查 create/claim/authorize/expire/renew、报告/Outcome 与替代的守卫、纯更新投影一致.
覆盖原始冲突、旧成功风险守卫, 不把“不含处置”的等价外推到治理行为.

`projectionSafety = normalSafety and projectionEquivalent`, 从合法正常/回调/重试前缀用 recoveryStep 继续抽样.
这是有限值域中每步的局部转换对照和场景证据, 不是所有参数/全部历史的等价证明.
组合模型原 50 条扩展 mutation 与 160 个 repeating/conflict 场景单独保留, 不能由投影取代.

## 4. 恢复组合与策略

恢复入口包含原正常的提交/完成/查询/读取/发现, 并加入 Coordinator/Worker 故障、lease 确认到期、墙钟回拨,
原 grant/报告/回调重投和回执处理. 回调重投依赖外部发送者已保留核验后的原 Report, 不临时创造新身份.
init/callbackRunningInit/callbackReleasedInit/retryPendingInit/retryAuthorizedInit 五组起点检查同一 safety.
最后一组从真实替代/授权/收到 grant 的前缀开始, 进一步观察重试后的完成与故障交错.

StopOnFailure 与 RetryOnce 仍是两个小策略. RetryOnce 是最多两尝试; 已知失败而安全依据不成立时提前停止,
可在接收时原子完成或由 normalStop 后续终结. Unknown/冲突/旧成功仍须保持对应阻塞.
接受与停止见证保存原定义、Handler binding 和 contractTime, 性质独立重算停止资格, 不用后来的窗口重解释过去.

补全中发现并修正: 新 Handler 声明较长 validThrough 时, 原 retryHandlerQualified 只检查新窗口,
允许原幂等保证已过期后的调用. `newHandlerCannotExtendOriginalWindowTest` 修复前实际失败, 修复后通过;
替代后授权/调用同时受原窗口与新窗口约束, `retryCallsOriginalContract` 独立回查调用时间和原 binding.
新增 mutation 刻意绕过守卫, 在原窗口 3 之后的时间 4 使用新声明窗口 6, 必须被指定性质检出.

## 5. 执行与实际记录

```sh
mix beamlet.check --jobs 4 --threads 4 --log-dir /tmp/beamlet-model-convergence-full
mix test
quint run model/quint/beamletRecovery.qnt --main recoveryAnalysis --init callbackReleasedInit \
  --step step --invariant safety --max-samples 1000 --max-steps 100 \
  --seed 123 --backend rust --n-threads 4 --verbosity 1 \
  --witnesses recoveryCompletionWitness callbackRedeliveryWitness policyStopWitness succeededReached failedReached
quint run model/quint/beamletExecution_test.qnt --main executionProjectionTests --init retryPendingInit \
  --step recoveryStep --invariant projectionSafety --max-samples 1000 --max-steps 100 \
  --seed 123 --backend rust --n-threads 4 --verbosity 1
```

默认 runner 已接入 16 个类型入口、239 场景、68 条预期反例及 43 组 / 59,000 条抽样.
其中原 34 组/46,000 条继续保留, 加独立核心 5,000、恢复五组各 1,000、投影三组各 1,000.
日志记录各自实际 init/step/invariant, 不把已在前缀成立的 witness 计作新事件.

实际结果分检查点记录, 不混淆最后修正前后的覆盖:

- 完整回归 `/tmp/beamlet-model-convergence-full` 退出 0: 16 类型入口、当时 238 场景、67 条预期反例通过;
  seed=42、jobs=4、threads=4, 42 组/58,000 条、每条最多 100 步未观察到对应 Safety/投影违规.
- 原窗口修正后定向场景 `/tmp/beamlet-convergence-final-scenarios.log`: 49 个正常场景通过;
  新 mutation 的检测场景另通过. 修复前失败证据为 `/tmp/beamlet-original-window-red.log`.
- 最终增量检查 `/tmp/beamlet-convergence-final` 退出 0: 全部 16 类型入口、239 场景通过;
  正常/恢复各四组与重试投影一组, seed=123、threads=4、每组 1,000 条, 共 9,000 条未观察到对应违规.
  八条正常 mutation 均产生实际违规与非空 ITF, 全部已解码; 新窗口反例另逐项核对原窗口、实际时间及调用数.
- 额外 retryAuthorizedInit 的 1,000 条恢复抽样退出 0, seed=123、threads=4、max-steps=100,
  日志 `/tmp/beamlet-convergence-retry-authorized.log`, 未观察到所检查 safety 违规.
  本轮合计 68,000 条完成抽样, 其中原窗口修正后完成 10,000 条增量, 不重复计算此前轮次的 56,000 条.
- Mix 工具/结构 12 个测试、格式检查通过; 修改的 Markdown/Elixir 文件主动诊断确认无发现.
  全部 103 个 Quint 文件满足结构测试, 本地 Markdown 链接均可解析.

下表为最后修正后 seed=123 的各组 1,000 条恢复轨迹, 各列可重叠.
正常从头开始的恢复 profile 容易早期失联/失效, 因而保留合法前缀观察后半段, 不以浅路径通过代替完成覆盖.

| init | 重启后终结 | 原回调重投 | 策略后续停止 | 成功 | 失败 | 安全替代 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| init | 8 | 2 | 0 | 7 | 1 | 0 |
| callbackRunningInit | 979 | 998 | 0 | 470 | 509 | 0 |
| callbackReleasedInit | 989 | 1000 | 0 | 500 | 489 | 0 |
| retryPendingInit | 351 | 0 | 351 | 0 | 351 | 644 |
| retryAuthorizedInit | 158 | — | — | 81 | 77 | — |

retryPendingInit 在该调度/时间窗口中未观察到重试后成功, 不据此声称该路径被覆盖.
正常 retryPendingInit profile 另实际观察到成功 357、失败 360、替代 1,000;
新增 retryAuthorizedInit 从替代/授权完成后的真实前缀观察调用与恢复交错, 已观察到新的成功与失败.
该组只收集终结/丢包/重启/到期见证, 表中未收集的列记为“—”, 不按零命中解释.
初始化已经存在的替代不作为该组新替代 witness, 计数不是成功率承诺或 Liveness 证明.

## 6. 工程契约与边界

本轮补充 [受限值与消息](../spec/persistent-values-and-messages.md)、[原子存储命令](../spec/storage-command-contracts.md)、
[Handler/回调/恢复策略](../spec/handler-recovery-contracts.md). 给出相等/预算、身份/冲突保留、时间与事务守卫、
启动重投、可信条件、停止策略及两个 SQL 后端的符合性用例; 具体 codec/物理 schema/真实 Adapter 尚无实现结果.

仍只完整展开一个 Intent 执行; 多 Intent 并发、真实 SQL/掉电、签名核验、资源幂等真实性/网络时限需工程验证.
不包含公平性/Liveness、完整迁移、清理、Byzantine 或外部 exactly-once. Q78 撤销专属授权仍后置.
没有新增 Runtime/Ecto 实现; 这些结果为抽象场景与有界抽样证据, 不是穷尽证明.
