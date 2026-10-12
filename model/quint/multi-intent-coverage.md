# 多 Intent 并发与调用方依赖验证

状态: 已补齐两个完整 Intent 的执行交错, 覆盖多个 Agent 独立创建及一个 Tool Call 等待多个 Intent.
复用独立执行核心和正常使用的纯规则, 保留既有模型/场景/反例. 本页是本次并发补充记录;
[核心切分](execution-core-coverage.md) 与 [第一轮正常补全](normal-use-coverage.md) 的历史采样不计入本次数量.
使用与工程责任见 [多 Intent / Tool Call 契约](../spec/multi-intent-and-tool-calls.md).

## 1. 状态、参与者和前提

[beamletMultiIntent.qnt](beamletMultiIntent.qnt) 绑定两个 Intent、两个 Agent、两个 Tool Call、两个共享 Worker,
每个 Intent 最多两个 Execution. report_id=1..4、lease 时钟=0..6、TTL=2、incarnation<=2、generation<=3;
默认不接受重复风险, 无可靠 fencing 能力. 消息是可丢失/延迟/乱序/重投的无序 Set.

| 状态 | 所有者/持久性 | 作用 |
| --- | --- | --- |
| multiStore | Beamlet 权威存储, 崩溃保留 | 全局提交身份目录; `intent -> {ledger, use}`; 共享可用性与可信契约时间 |
| sharedWorkers | Worker 易失会话 | `worker -> {alive, incarnation, intent -> LocalState}`; 一个进程的崩溃同时清空所有 Intent 槽 |
| multiNetwork | 无序消息介质 | 带 Intent 作用域的启动/报告/回执, 带 Agent 路由的提交请求/回复 |
| resources | 独立外部事实 | `intent -> ExternalState`; 外部完成不直接改变任何权威 Outcome |
| multiClock | Authority 墙钟 | 可前跳/回拨; 与不回拨的抽象 contractTime 分开 |
| callerRounds | 调用方自己的持久存储 | 原依赖清单、owner、已提交汇总; 不属于 Beamlet 的 Ledger |
| agentLocals | Agent 易失状态 | 提交身份解析后的引用及读到的结果缓存; 崩溃清空, 重启重建 |
| scopeObservation | 仅验证见证 | 一次转换的独立前后状态, 对照实际 post-state 后检查非目标 Intent 不被串写 |

两个 Intent 故意复用相同局部 Execution/report/token 数字. 不同 Intent 的幂等上下文分别为 1/2;
回调 correlation 是本有界域内的独立 opaque 身份, 算术表示不规定公开编码.
`registered` 保留调用方最初清单的独立见证, 不批准额外产品字段. 导入的单 Intent 状态不参与本入口运行;
新增 ITF 的协议/观察变量为上述八组, 不混入原单 Intent 的另一套活动状态.

继承非 Byzantine Worker、已提交事务不丢失、可信消息/回调核验与资源幂等条件等前提.
不验证签名/ACL 实现, 不假定最终投递、公平调度或最终完成. 两个外部资源事实分开, 不模拟同一业务对象竞争.
沿用原模型的原子 Authority 与消息集合适配, 避免引入第二套编排框架; 所有纯执行规则仍来自原独立核心.

## 2. 组合规则与检查

[multi/](multi/) 分开 state、logic、submission、execution、reports、recovery、properties 和 scheduling.
create/claim/authorize/lease、Worker 调用/报告、证据/Outcome 与安全替代复用既有纯计算;
适配层添加 Intent 路由、独立 Handler/回调绑定和共享进程会话. 不改变单 Intent 或治理规则.

- `multiExecutionSafety`: 每个 Intent 独立检查唯一/不可变 Outcome、授权/调用/提交见证、审计、证据与原幂等窗口;
  已存报告还须来自该 Intent 的独立资源发送事实, 防止局部 token 相同导致串线.
- `directoryScoped`: collection 内稳定提交身份唯一、原定义/上下文对应正确 Intent; 同身份同定义复用, 异定义冲突.
- `sharedSessionsSafe` / `transportScoped`: 同一 Worker 的所有槽共享 alive/incarnation; grant/receipt 对应该 Intent
  的持久事实; Envelope 的 Intent scope 与局部载荷先关联再解释.
- `scopeIsolation`: 观察快照必须等于真实 post-state; 一次 Intent 操作不改变另一个 Intent 的账本、业务使用状态、资源或
  Worker 槽. 整个 Worker 会话故障和全局时钟更新明确作为共享事件; 已有 Outcome 和目录定义始终保留.
- `callerFactsScoped`: Agent 只能把该轮依赖对应 Intent 的已提交 Outcome 读入指定 slot, 不能读另一轮/Agent 的引用.
- `toolRoundsSound`: 依赖清单不偏离原登记, 每个 slot 恰有正确结果才汇总; 数量相等不够, 重复通知/结果不补齐缺失 slot.

调用方模型采用等待全部终态的组合示例, 包括 Succeeded/Failed/Cancelled; Pending/Unknown 不是结果.
没有隐式兄弟取消、跨 Intent 回滚或组事务. 调用方的清单与汇总持久性是明确前提, 不声称 Beamlet 恢复 Agent 调用栈.

## 3. 场景与反例

[beamletMultiIntent_test.qnt](beamletMultiIntent_test.qnt) 聚合 42 个确定场景, 位于
[scenarios/multi/](scenarios/multi/):

- 多 Agent 提交与相同 key 不同 namespace、同身份复用、异定义冲突、unkeyed 独立创建及反向提交到达.
- 相同局部 token 的共享 Worker 执行, grant/report/receipt 错路由拒绝, 回调 correlation/认证拒绝及回调乱序.
- 共享 Worker 释放/重启、实际在途的旧 grant 拒绝、Coordinator 离线后回调完成、重投不重复终结、lease 回拨屏障.
- 单 Intent Unknown/重试/取消不串改另一个; 原幂等窗口仍限制替代调用.
- 双依赖的不同业务值、混合成功/失败/取消、部分完成拒绝汇总、重复读取不重复计数、同 Intent 有意对应两个 slot.
- 调用方崩溃后保留清单、重提稳定身份并重建结果, 丢回复后取回 Closed 原结果, 同 Agent 的两个 Tool Call 分离.

[beamletMultiIntent_mutations_test.qnt](beamletMultiIntent_mutations_test.qnt) 的八个 BUG 与实际 ITF:

| BUG / 模块 | 故意错误 | 指定检查 | ITF 状态数 |
| --- | --- | --- | ---: |
| 1 / multiCrossIntentReport | A 的 Worker 报告写入相同局部 token 的 B | 已存报告对应本 Intent 独立发送事实 | 21 |
| 2 / multiCrossIntentGrant | A 的许可投到 B 的 Worker 槽 | sharedSessionsSafe | 13 |
| 3 / multiSharedIdempotencyContext | B 的实际调用使用 A 的幂等上下文 | multiExecutionSafety | 18 |
| 4 / multiSiblingHistoryErased | 操作 A 时清除 B 的 History | scopeIsolation | 19 |
| 5 / multiPrematureToolJoin | 只有一个依赖有结果就完成整轮 | toolRoundsSound | 25 |
| 6 / multiJoinByNotificationCount | 两条结果都计到 slot 1, 按条数完成双依赖 | toolRoundsSound | 28 |
| 7 / multiCallbackCorrelationCollision | B 保存 A 的回调关联 | multiExecutionSafety | 19 |
| 8 / multiLostDependencyManifest | Agent 崩溃后遗漏原清单中的 B | toolRoundsSound | 8 |

所有 mutation 从合法转换构造前缀, 初始末态检查 multiSafety; 最后一步故意违规. ITF 包含前缀与最后转换,
八份均已解码、检查真实状态变化, 并核对相应语义. 使用指定子性质, 不靠不相关的全局快照不一致检出.
BUG 1 的 B 外部资源仍 ResourceUnfinished、emitted 为空, 却被 A 的 Success/value=1 终结.
BUG 3 的期望 context=2、实际调用 context=1. BUG 6 有两条真实终态结果, 但 slot 集合只有 `{1}`, 缺少 slot 2.

## 4. 运行起点与实际结果

| init | step | 检查侧重 |
| --- | --- | --- |
| independentInit | healthyStep | 两个 Agent 各保存自己的单依赖清单并独立提交; 正常完整执行和结果收集 |
| joinedInit | healthyStep | 一个 Agent 的双依赖清单, 回复/完成乱序与按身份汇总 |
| releasedPairInit | step | 两个真实外部调用已发起并登记 Pending; 共享 Worker 释放后的回调/故障组合 |
| unknownPairInit | healthyStep | A 已经合法进入 Unknown, B 可独立推进; 新证据也可解决 A |
| retryPairInit | step | A 合法替代并收到新 grant, B 已运行; 重试调用与恢复交错 |
| emptyInit | step | 从空目录/空调用方清单开始, 所有提交/执行/故障组合 |

前缀通过真实命令建立, 不直接注入 Running/Closed. healthyStep 排除故障/主动取消, step 组合正常和故障选择.
调度只为当前操作选择相关参数, 避免无关 nondet 的笛卡尔积; 不通过空转分支放宽可达行为.

本次完成:

- 19 个类型入口、`239 + 42 = 281` 个正常场景通过; 原场景完整保留并重跑.
- 76 条 mutation 检测场景/指定不变量违规与 ITF 检查通过, 包括原 68 条与新增八条.
- `/tmp/beamlet-multi-final`: seed=42、Rust、每进程四线程、最多三个并行任务、每条最多 100 步.
  independentInit/healthyStep 10,000 条, 其余五组各 1,000 条, 合计 15,000 条未观察到 multiSafety 违规.
- `/tmp/beamlet-multi-witness-final`: seed=123、相同后端/线程/步数, 五个定向组各 1,000 条, 合计 5,000 条通过.
  这一检查点收紧恢复见证: 必须是完成该轮的 owner 本人重启; Worker 释放完成必须是执行两个 Intent 的那个 Worker,
  且两个 Outcome 均为明确成功/失败. 安全性质与执行规则没有变化; 较早检查点的宽见证数不用于下表.
- 类型/场景日志在 `/tmp/beamlet-multi-regression-{typecheck,test}`, 全部反例在 `/tmp/beamlet-multi-mutations-final`;
  `multi-decoded.json` 保存新增八份解码后的关键前后状态. 模拟目录 `results.json` 记录完整实际参数和退出结果.

本次实际采样合计 **20,000 条**, 不含开发冒烟采样. 没有重新运行全部历史采样组, 不把新默认预算当作本次已执行总量.
原单 Intent 安全规则未修改, 既有确定场景与全部反例重新检查.

| 检查组 | 双依赖汇总 | 部分结果等待 | owner 重启后汇总 | 共享 Worker 释放后两个明确完成 | Unknown 与另一个 Closed 并存 |
| --- | ---: | ---: | ---: | ---: | ---: |
| independentInit, seed=42, 10,000 条 | — | — | — | — | — |
| joinedInit, seed=123, 1,000 条 | 976 | 1,000 | 0 | 0 | 0 |
| releasedPairInit, seed=123, 1,000 条 | 174 | 690 | 153 | 221 | 0 |
| unknownPairInit, seed=123, 1,000 条 | 1,000 | 1,000 | 0 | 0 | 768 |
| retryPairInit, seed=123, 1,000 条 | 130 | 678 | 120 | 21 | 193 |
| emptyInit, seed=123, 1,000 条 | 114 | 546 | 114 | 0 | 12 |

independentInit 的 10,000 条另观察到两个独立 Agent 均收集结果 9,835 条、两 Intent 均调用 9,997 条、
同一 Worker 执行两个 Intent 5,056 条. 表中“—”表示该组主要看独立 Agent 指标, 不把不同用法混合解读.
各列可重叠, 前缀已存在的调用/共享 Worker 不算新的进展; Closed 包括显式 Cancelled, 不等于业务成功.
emptyInit 故障组实际观察到双调用仅 4 条、释放后的两个明确完成为 0; 因而保留正常组和合法深前缀覆盖,
不把该组的浅路径/取消看成完整完成覆盖. 计数不是概率承诺或 Liveness 证明.

## 5. 复现与剩余边界

```sh
mix beamlet.check --phase typecheck --jobs 4 --threads 4
mix beamlet.check --phase test --jobs 4 --threads 4
mix beamlet.check --phase mutations --jobs 4 --threads 4
quint run model/quint/beamletMultiIntent.qnt --main multiIntentAnalysis \
  --init independentInit --step healthyStep --invariant safety --max-samples 10000 --max-steps 100 \
  --seed 42 --backend rust --n-threads 4 --verbosity 1 --witnesses independentWitness sharedWorkerWitness
quint run model/quint/beamletMultiIntent.qnt --main multiIntentAnalysis \
  --init releasedPairInit --step step --invariant safety --max-samples 1000 --max-steps 100 \
  --seed 123 --backend rust --n-threads 4 --verbosity 1 --witnesses joinedWitness recoveredJoinWitness releasedCompletionWitness
```

runner 新增三个类型入口、42 场景、八个 mutation 和六个采样组; 默认独立 Agent 主组用 samples=5,000,
其余五组用 directed_samples=1,000. 总计 **49 组 / 69,000 条** 默认预算. 不改变原入口/BUG 或历史组合检查.
结构测试覆盖四个首版入口, 全部 121 个 Quint 文件仍须无环且每文件 <=200 行; Mix 工具/结构测试共 12 个.

仍未验证任意数量 Agent/Intent、共享资源限流/容量/扫描公平性、跨权限域的真实认证、实际 SQL 并发/锁/掉电,
真实 codec/回调签名/外部 key 无碰撞、provider 时限/幂等真实性、同一业务对象并发、跨 Intent 原子事务或最终完成.
没有 Runtime/Ecto 实现. 这些结果是场景、反例有效性和有界采样证据, 不是穷尽证明.
