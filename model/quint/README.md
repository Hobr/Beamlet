# Quint 可执行规格

模型检查 Beamlet 的执行, 结果接受, 恢复及有界并发安全关系. 设计与首版范围从
[文档索引](../README.md) 阅读; 需求映射, 检查结果和假设见 [模型覆盖与边界](coverage.md).

## 模型入口

| 入口 | 用途 | main |
| --- | --- | --- |
| [beamletExecution.qnt](beamletExecution.qnt) | 首版独立执行核心, 不含协调/治理账本 | executionAnalysis |
| [beamletNormalUse.qnt](beamletNormalUse.qnt) | 提交, Handler, 同步/回调/查询, 停止, 事实读取与发现 | normalUseAnalysis |
| [beamletRecovery.qnt](beamletRecovery.qnt) | 正常能力与崩溃, 丢包, 重投, 到期, 时钟回拨组合 | recoveryAnalysis |
| [beamletMultiIntent.qnt](beamletMultiIntent.qnt) | 两个完整 Intent, 两个 Agent, 共享 Worker 与调用方依赖汇总 | multiIntentAnalysis |
| [beamletExecution_test.qnt](beamletExecution_test.qnt) | 独立核心与无处置参考账本的投影对照, 仅用于测试 | executionProjectionTests |
| [beamletCore.qnt](beamletCore.qnt) | 完整执行/协调/治理组合参考 | beamletCoreAnalysis / repeatAllowed / fenced |
| [beamletReconciliation.qnt](beamletReconciliation.qnt) | 协调原语与命令协议 | beamletReconciliation |
| [beamletConflicts.qnt](beamletConflicts.qnt) | 防御性冲突, 全部排除与部分取代 | beamletConflicts |
| [beamletRules.qnt](beamletRules.qnt) | 规则版本, 普通退役 | beamletRules |
| [beamletWithdrawals.qnt](beamletWithdrawals.qnt) | 范围撤销及命令重投 | beamletWithdrawals |

根目录的 `_test.qnt` 聚合确定场景, `_mutations_test.qnt` 提供故意错误入口.
`beamletConflicts_test.qnt` 同时提供分离的正常和 mutation 实例. 完整入口与运行配置由
[Quint 检查器](../../tools/beamlet/quint_checks.ex) 管理.

## 检查命令

使用 Quint 0.32.0, 默认 Rust 后端. 从仓库根目录运行:

```sh
mix beamlet.check
mix beamlet.check --samples 20 --directed-samples 20
mix beamlet.check --phase typecheck
mix beamlet.check --phase test
mix beamlet.check --phase simulate
mix beamlet.check --phase mutations
mix test
```

`mix test` 验证工具和模型结构, 不代替 Quint 场景及采样.
默认接入 19 个类型入口, 281 个正常场景, 76 条预期反例和 49 组模拟; 默认模拟预算为 69,000 条, 每条最多 100 步, seed=42.
预算配置与已经完成的采样结果分别记录, 见覆盖文档.

```sh
mix beamlet.check --jobs 4 --threads 4 --log-dir /tmp/beamlet-quint
quint run model/quint/beamletMultiIntent.qnt --main multiIntentAnalysis \
  --init releasedPairInit --step step --invariant safety \
  --max-samples 1000 --max-steps 100 --seed 123 --backend rust --n-threads 4 \
  --witnesses joinedWitness recoveredJoinWitness releasedCompletionWitness
```

| 参数 | 含义 |
| --- | --- |
| --samples | 核心基线, 独立执行和独立 Agent 主组的采样预算, 默认 5,000 |
| --directed-samples | 定向组的预算, 默认 1,000 |
| --jobs | 独立检查进程并发数 |
| --threads | 每个 Rust 模拟进程的线程上限; 单样本 mutation 固定使用 1 线程 |
| --log-dir | 日志, ITF, 运行参数和耗时报告目录; 省略则使用临时目录 |

未指定 threads 时, 工具按在线 scheduler 数与 jobs 分配保守线程预算.
日志目录包含 `run-info.txt`, `timings.tsv` 和各任务输出; 复用目录会重写本次汇总, 并清除待检查 mutation 的旧 ITF.
只有退出码 1, 实际 `Invariant violated` 和非空 ITF 同时成立才算预期反例; 解析, 类型或运行错误不算检出.
单条反例复现见 [mutation 索引](counterexamples.md).

## 源码结构

| 目录 | 职责 |
| --- | --- |
| base/ | 类型, 参数, 默认值与状态所有者; execution_* 为独立执行, 原 types/state 为组合参考 |
| logic/ | 纯守卫, 证据解释, 投影与更新; 参考 adapter 显式维护协调判断版本 |
| actions/ | 完整状态赋值的协议动作 |
| properties/ | Safety 子性质与可达性见证 |
| normal/ | 提交目录, Handler, 回调, 策略, 读取及恢复组合 |
| multi/ | Intent 作用域, 共享 Worker, 调用方依赖, 隔离性质与调度 |
| scenarios/ | 按严格执行, 资源排除, 正常使用, 并发, 协调/冲突划分的 fixture 和确定场景 |
| mutations/ | 从合法前缀出发的故意错误转换 |

阅读单 Intent 执行时, 从入口进入 [执行状态](base/execution_state.qnt), [共同类型](base/execution_types.qnt),
再按问题进入 logic/actions/properties.并发状态见 [multi/state.qnt](multi/state.qnt).
依赖方向为入口 → 动作/性质 → 纯逻辑 → 公共状态/类型; 首版入口不依赖治理参考或测试/mutation.
共同执行参数只在 `base/execution_values.qnt` 声明, 执行与参考账本共享纯 lease, 报告及 Worker 计算.
命令/治理内部仍共用参考账本; 投影对照限制普通行为漂移, 不声称治理行为等价.

## 修改模型时

- 每个实例共用未绑定 fixture, 参数只在最外层入口绑定. Quint 0.32 的跨模块重复绑定可能通过类型检查, 却在执行时报
  `Uninitialized const`.
- 场景通过真实转换建立前缀, 不直接注入 Running/Closed; 拒绝场景检查守卫及 disabled action.
- 正常 step 不导入 mutation, 不以 Open 的兜底空转代替进展. 故障采样与正常 profile 分开, 以合法深前缀覆盖后半段.
- 辅助见证独立回查真实状态, 不成为执行守卫或公开 schema.保留观察以检出重复终结, 旧许可调用和跨 Intent 串写.
- [结构测试](../../test/quint_structure_test.exs) 检查全部导入无环, 每文件最多 200 行, 以及四个首版入口的依赖隔离.
- 语义修改同步更新守卫, 性质, 场景与相应 mutation.类型/场景检查后运行相关定向采样; 跨层变化再做完整回归.
  文档整理不需要重新运行全量采样.

当前使用场景与随机模拟, 没有执行 Apalache 符号验证, 更不构成无界穷尽证明. 模型依赖原子存储, 合规 Worker,
可信消息入口和明确的外部资源契约; 不保证最终投递, 公平调度或最终完成. 具体收窄及工程边界统一见覆盖文档.
