# Quint 可执行规格

这些模型检查 Beamlet 的执行, 结果接受, 恢复及有界并发安全关系.
产品设计从 [文档索引](../README.md) 阅读; 本文供运行检查或研究模型时查阅.

## 模型入口

| 入口 | 用途 | main |
| --- | --- | --- |
| [beamletExecution.qnt](beamletExecution.qnt) | 首版独立执行核心, 不含协调/治理账本 | executionAnalysis |
| [beamletNormalUse.qnt](beamletNormalUse.qnt) | 提交, Handler, 同步/回调/查询, 停止, 事实读取与发现 | normalUseAnalysis |
| [beamletRecovery.qnt](beamletRecovery.qnt) | 正常能力与崩溃, 丢包, 重投, 到期, 时钟回拨组合 | recoveryAnalysis |
| [beamletMultiIntent.qnt](beamletMultiIntent.qnt) | 两个完整 Intent, 两个 Agent, 共享 Worker 与调用方依赖汇总 | multiIntentAnalysis |
| [beamletContinuation.qnt](beamletContinuation.qnt) | 三 Intent, 单步部分结果决策, 后续身份与调用方重启恢复 | continuationAnalysis |
| [beamletClaim.qnt](beamletClaim.qnt) | 领取分配提交, 回复丢失/重投, 会话隔离 | claimAnalysis |
| [beamletResource.qnt](beamletResource.qnt) | 设备/账户/对象/协议匹配, 授权绑定与实际调用 | resourceAnalysis |
| [beamletHistory.qnt](beamletHistory.qnt) | 两 Coordinator 草稿, History 与状态原子提交, 逻辑次序 | historyAnalysis |
| [beamletTriple.qnt](beamletTriple.qnt) | 三原始并发依赖, 两项完成后调用方重启 | tripleAnalysis |
| [beamletSharedResource.qnt](beamletSharedResource.qnt) | 两 Intent 竞争同一资源版本, 原 key receipt 恢复 | sharedResourceAnalysis |
| [beamletExecution_test.qnt](beamletExecution_test.qnt) | 独立核心与无处置参考账本的投影对照, 仅用于测试 | executionProjectionTests |
| [beamletCore.qnt](beamletCore.qnt) | 完整执行/协调/治理组合参考 | beamletCoreAnalysis / repeatAllowed / fenced |
| [beamletReconciliation.qnt](beamletReconciliation.qnt) | 协调原语与命令协议 | beamletReconciliation |
| [beamletConflicts.qnt](beamletConflicts.qnt) | 防御性冲突, 全部排除与部分取代 | beamletConflicts |
| [beamletRules.qnt](beamletRules.qnt) | 规则版本, 普通退役 | beamletRules |
| [beamletWithdrawals.qnt](beamletWithdrawals.qnt) | 范围撤销及命令重投 | beamletWithdrawals |

根目录的 `_test.qnt` 聚合确定场景, `_mutations_test.qnt` 提供故意错误入口.
`beamletConflicts_test.qnt` 同时提供正常和 mutation 实例.
完整入口, mutation 名称, 检查目标和预算由 [检查器](../../apps/beamlet_specs/lib/mix/quint_checks.ex) 管理.

## 检查命令

使用 Quint 0.32.0, 默认 Rust 后端, 从仓库根目录运行:

```sh
mix quint typecheck
mix quint test
mix quint simulate
mix quint mutations
mix test
```

`mix quint` 默认运行全部阶段, 等同于 `mix quint all`.
`mix test` 检查工具和文件结构, 不运行 Quint 场景或采样.
快速运行可降低采样预算:

```sh
mix quint --samples 20 --directed-samples 20 --jobs 4 --threads 2 --log-dir /tmp/beamlet-quint
```

| 参数 | 含义 |
| --- | --- |
| --samples | 核心基线, 独立执行和独立 Agent 与部分推进主组的采样预算, 默认 5,000 |
| --directed-samples | 定向组的预算, 默认 1,000 |
| --jobs | 独立检查进程并发数 |
| --threads | 每个 Rust 模拟进程的线程上限; 单样本 mutation 固定使用 1 线程 |
| --log-dir | 日志, ITF, 运行参数和耗时报告目录; 省略则使用临时目录 |

未指定 threads 时, 工具按在线 scheduler 数与 jobs 分配线程预算.
默认模拟配置为 67 组/91,000 条轨迹, 每条最多 100 步, seed=42; 这是配置预算.
日志目录包含 `run-info.txt`, `timings.tsv`, 各任务输出和反例 ITF, 不纳入源码.
复用日志目录会重写汇总并清除待检查 mutation 的旧 ITF.

单独模拟某个起点, 例如 Worker 已释放后的恢复:

```sh
quint run model/quint/beamletMultiIntent.qnt --main multiIntentAnalysis \
  --init releasedPairInit --step step --invariant safety \
  --max-samples 1000 --max-steps 100 --seed 123 --backend rust --n-threads 2 \
  --witnesses joinedWitness recoveredJoinWitness releasedCompletionWitness
```

## 反例检查

Mutation 从正常命令建立的合法前缀出发, 执行故意错误转换, 检查指定性质能否检出.
正常模型不导入这些错误动作. `mix quint mutations` 运行全部 97 条, 可在检查器中查找单条入口和模块名.

例如, 检查用新 Handler 的更长窗口绕过原幂等保证:

```sh
quint run model/quint/beamletNormalUse_mutations_test.qnt --main normalExtendedIdempotencyWindow \
  --init mutantInit --step mutantStep --invariant mutantInvariant \
  --max-samples 1 --max-steps 1 --seed 42 --backend rust --n-threads 1 \
  --out-itf /tmp/normal-extended-window.itf.json
```

只有退出码 1, 实际 `Invariant violated` 和非空 ITF 同时成立才算检出; 解析, 类型或运行错误不算.
ITF 包含合法前缀和违规转换, 状态数可以大于两条. 97 条反例不表示所有可能错误都被覆盖.

## 模型边界

| 模型组 | 状态与范围 |
| --- | --- |
| 单 Intent 执行/恢复 | Authority 持久账本, Worker 易失会话, 无序消息, 外部事实与可跳变墙钟; 正常使用增加提交目录和 Handler/完成绑定 |
| 多 Intent | 两个完整账本, 两 Agent/Tool Call, 共享 Worker, 调用方持久 manifest/aggregate |
| 部分结果推进 | 三 Intent, 两轮清单, 一个调用方持久决策槽; 固定单步规则从已读 Succeeded 驱动下一 Intent |
| Claim | 持久分配与请求/回复分开, Worker 只持有已接收 token; 旧回复不是当前启动许可 |
| 资源匹配 | 一个逻辑目标, 两设备/账户/对象/协议值, 每 Execution 保存 binding; 最多 4 次环境变化 |
| History | 一个 Intent, 两 Coordinator 草稿, 至多 6 个提交组; 检查创建/领取/授权/报告/终结与重复报告 |
| 三并发依赖 | 三个完整账本, 一个调用方/一轮三 slot; 两项完成后清空缓存并从原清单重建 |
| 共享资源 | 两个完整账本, 一个对象及初始版本 0, 请求绑定 receipt; applied/version_mismatch 均为 Success 数据 |
| 协调/治理参考 | 判断版本, 原命令结果, 冲突处置, 显式取代范围, 固定规则版本与退役/撤销 |

执行实例最多两个 Worker, 每 Intent 两个 Execution; 墙钟 0..6, TTL=2, incarnation 至多 2, generation 至多 3.
Report/协调 Command ID 域为 1..4, 耗尽后不复用身份. 账本与审计列表仍可增长,
因此限制参与者, 身份域与轨迹长度不等于穷尽有限状态空间.

- 原子权威事务持久保留, Worker 合规, 消息入口可信. 消息可丢失, 延迟, 乱序, 重复,
  不假定最终投递, 公平调度或人工最终响应; 不模拟 Byzantine 伪造.
- 授权与外部调用不原子. 旧许可持有者可能在 lease 到期或取消后调用;
  控制请求被拒绝, 负面查询或没有报告均不能证明外部停止或未执行.
- `ALLOW_REPEAT=true` 表示明确接受重复风险. fenced 实例另假定资源协议永久排除旧尝试未来执行并确认尚未发生;
  generation 本身不提供外部 fencing.
- Handler 能力, 签名核验, 资源环境, 幂等 scope/窗口都是已核验输入.
  `verified` 不证明真实验签, correlation 不是凭据, 模型中的算术 correlation 仅在参数域内单射.
  contractTime 是不可回退的资源时间抽象, lease 墙钟回拨不延长幂等窗口.
- RetryOnce 最多建立两个尝试; 预算不能压过 Unknown, 冲突或旧成功.
  读取假定已提交一致快照, 发现只提供候选. 不模拟生产退避, 容量, 分页, 索引或扫描公平性.
- 调用方持久清单, 决定及汇总的原子性是前提. 决定, 后续清单, Beamlet 提交分别保存,
  没有跨存储共同事务, 不恢复调用栈或隐式取消兄弟. 汇总不保证后续副作用只执行一次.
- History 以组序号/事件位置表示逻辑次序, 固定解释版本. 完整前后快照和独立 committed 记录用于检查原子关联,
  不是产品字段要求. 草稿与提交时间相等是保守收窄, 实现应按取得事务保护后的当前时间重验.
- 共享资源假定外部原子 CAS 与请求绑定 durable receipt; 资源修改与接受 Outcome 分开.
  当前内容, mtime, rename 或 Browser 页面状态不能替代原请求证据.
- 协调/治理中的依据, 规则与权限是可信输入. 判断版本相同仍重验条件, 普通退役不撤销处置,
  全部排除可保持 Unknown, 撤销不恢复旧处置或创建 Outcome/重试许可.
  撤销专属授权的区别和 Closed 后历史纠正尚未建模.
- 各模型独立检查, 不声称验证其全部交叉组合. 原执行/multi 实例合并 Claim 与得知 token,
  Claim 实例另展开两者. 投影检查只比较无协调处置的普通行为.
  首次结果, 提交/调用观察及重启动作记录只是检查见证, 不授予权限.

### 验证结果

检查记录包括 33 个类型入口, 360 个确定场景, 97 条实际反例和 13 个 Mix 测试通过.
Claim, 资源, History, 三依赖与共享条件写的 13 个组共采样 13,000 条有效轨迹, seed=42,
每条最多 100 步, 未观察到所检查 Safety 的违规. 全部 67 个模拟组另以每组 1 条运行验证配置连接.
双 Intent 与部分推进还有独立历史采样, 不将它们当作当前全部模型已重跑的证据.

成功见证表示在给定前缀与调度下可达, 不证明最终完成; 前缀已有事实不是后续进展, 计数也不是完成概率.
没有 Apalache 符号验证, 无界穷尽或公平性证明.
人工审批目前只由通用 Pending/回调抽象覆盖, 尚无完整审批创建/恢复协议模型; 混合版本与旧 reader 兼容也未独立建模.
真实 SQL 隔离/持久性, codec, 认证/ACL, provider 的窗口/receipt, 旧数据迁移与性能仍需工程验收;
模型不证明 Runtime 实现, Authority 迁移或外部 exactly-once.

## 源码结构

| 目录 | 职责 |
| --- | --- |
| base/ | 类型, 参数, 默认值与状态所有者; execution_* 为独立执行, 原 types/state 为组合参考 |
| logic/ | 纯守卫, 证据解释, 投影与更新; 参考 adapter 显式维护协调判断版本 |
| actions/ | 完整状态赋值的协议动作 |
| properties/ | Safety 子性质与可达性见证 |
| normal/ | 提交目录, Handler, 回调, 策略, 读取及恢复组合 |
| multi/ | Intent 作用域, 共享 Worker, 调用方依赖, 隔离性质与调度 |
| continuation/ | 调用方持久决定, 消费证据, 下一轮清单, 独立性质与恢复见证 |
| contracts/ | Claim 响应, 资源匹配, History 提交, 三原依赖与共享条件写的独立有界例子 |
| scenarios/ | 按严格执行, 资源排除, 正常使用, 并发, 协调/冲突划分的 fixture 和确定场景 |
| mutations/ | 从合法前缀出发的故意错误转换 |

阅读执行逻辑时从 [执行状态](base/execution_state.qnt) 和 [共同类型](base/execution_types.qnt) 进入
logic/actions/properties. 依赖方向为入口 → 动作/性质 → 纯逻辑 → 公共状态/类型; 首版入口不依赖治理参考或测试/mutation.
共同执行参数在 `base/execution_values.qnt` 声明, 执行与参考账本共享纯计算.
[结构测试](../../apps/beamlet_specs/test/quint_structure_test.exs) 检查导入无环, 单文件不超过 200 行与首版依赖隔离.
