# 正常使用覆盖与 SPEC 一致性审查

状态: 本页保留补全前的审查证据和缺口清单. 后续已按用户要求增加
[正常闭环补全](normal-use-coverage.md), 对应独立回调、提交身份/业务值、Handler 条件与失败原子接受.
后续进一步增加 [执行核心隔离与恢复组合](execution-core-coverage.md), 并细化首版工程契约.
以下“当前/本轮/尚未”均指本页原审查检查点; 最新抽象、场景、验证边界及运行结果以这两份后续记录为准.
原结论: 执行子集有可执行主路径, 审查抽样未观察到所检查 Safety 的违规; 当时不能视为首版正常能力的完整模型.
测试数量、无反例与产品覆盖完整是三件不同的事. 本页不要求特殊情况下的绝对可靠, 不新增 Runtime 实现或产品协议决定.

## 1. 审查口径

正常闭环包括稳定提交/复用、兼容 Handler 执行、同步结果、durable Pending 后独立完成、
声明条件支持时的重试、结果/事实读取. 重投、进程释放与普通恢复也是 durable 运行方式, 不全部归为罕见灾难.
单个 Intent 的 Safety 可以单独建模; 不要求把 codec、真实 SQL、认证密码学和所有 Intent 一起塞进 Quint.
但正常产品需求至少须有明确抽象及对应验证位置, 不能用抽象已存在代替尚未表达的语义.

对照 [核心 SPEC](../spec/core-state-machines.md)、[Handler SPEC](../spec/operation-handler-contracts.md)、
[lease SPEC](../spec/leases-and-permissions.md) 和 [首版范围](../spec/first-release-scope.md).
源码核对范围为 base、核心 logic/actions/properties、严格/重复/资源排除场景; 协调/治理复用既有语义记录和本轮全场景回归,
不是对每项治理性质重新作独立证明. Q78 授权区分仍未新增模型验证.

## 2. 正常路径与覆盖缺口

| SPEC 要求 | 模型/可执行依据 | 判断 |
| --- | --- | --- |
| 持久启动授权先于外部执行, incarnation/generation 区分 | leases/workers 的独立动作; authorizationIsNotExecutionTest、duplicateGrantDoesNotInvokeAgainTest | 已覆盖抽象协议 |
| 合格同步成功、报告与 Outcome/Closed/History 联动 | recordAndMaybeCommit; successCommitTest、completionWinsTest | 已覆盖抽象成功路径 |
| 已知失败后按依据终结 | ordinarySourceEligible / finishFailure; knownFailureCanCloseTest | 可执行, 但停止策略/预算未表达, 失败报告与终结分两步 |
| 显式取消不证明外部停止, 首个合格终结获胜 | cancelWithoutExecutionTest、cancellationWinsTest、cancellationBeforeGrantDeliveryTest | 已覆盖抽象竞争 |
| Pending 保存后 Waiting, 不因 lease 到期回退, 完成先到不倒退 | pendingSurvivesWorkerLossTest、latePendingCannotRegressTest、completionBeforePendingIsProducedTest | 状态投影已覆盖, 完成入口只部分覆盖 |
| 不支持查询的回调型 Pending, 释放原 Worker 后仍能完成 | publishCompletion 依赖原 Worker 存活及本地 started; Worker 丢失场景使用 queryExternal | **正常覆盖缺口**: 无独立回调生成路径/持久关联; 不能用查询替代其验证 |
| 安全替代与旧证据保留 | preparedReassignmentTest、fencedReplacementTest、duplicateEffectsButOneOutcomeTest; 正常环境审查的失败后重试 | 已覆盖未授权重领、可靠排除/明确重复风险; 不等于覆盖外部幂等重试 |
| Submission Key 定位既有 Intent、定义冲突拒绝、Closed 复用结果 | init 从已经存在的 Open Intent 开始; Ledger 没有提交 key、不可变定义及 find/create 命令 | **正常覆盖缺口**; 协调 Command ID 不是 Submission Key |
| 输入/结果的逻辑内容、同身份变更内容冲突、结果不可变 | Report 只有 id/exec/kind/origin, Outcome 只有 kind/exec; 冲突测试区分 kind | **抽象不完整**: 无法区分两个不同成功值或验证原业务结果复用; 不必为此建完整 JSON codec |
| 按 Handler 支持条件选择查询、幂等/重试, 保持原协议解释 | ALLOW_REPEAT/CAN_FENCE 常量; queryExternal 无查询能力条件; 无 Operation/Handler 身份、能力快照或 Idempotency Context | **部分覆盖**: 可研究所选环境的安全性, 不能代表所有正常 Handler 契约 |
| Coordinator 重启保留持久事实、结果与远端 lease | coordinatorRestartPreservesLeaseTest、oldReportAfterWorkerRestartTest; authority.durable 保留 | 已覆盖抽象状态保存; 工作扫描/重发现、读取接口不是已验证动作 |
| 多 Coordinator 原子处理, 不同 Intent 可并发; 两种 SQL 后端 | 原子 Ledger 转换, 单 Authority/Intent, 两个 Worker | 合理模型边界, 后续 Storage 符合性验证; 尚未验证实际 SQL 隔离/并发 |

### 一个必须明确的 SPEC 对齐点

核心 SPEC 6.3 要求普通合格完成默认同事务保存报告、更新 Execution、接受 Outcome/Closed/History. 当前 Success
直接走这一联动; Failure 先保存证据且保持 Open, 再由 finishFailure 终结, 场景明确检查了这个中间状态.
这可以解释为报告到达时尚未作出“不再尝试”的策略决定, 并非已证明存在非法终结;
但策略输入及“已经合格的失败报告与终结同事务”路径没有表达. 在统一抽象与场景前,
不能声称全部普通完成都验证了同一原子接收契约.

## 3. 实际执行结果

本轮全部通过:

- `mix beamlet.check --phase typecheck --jobs 4 --threads 2 --log-dir /tmp/beamlet-normal-use-audit-types`: 10 个入口.
- `mix beamlet.check --phase test --jobs 4 --threads 2 --log-dir /tmp/beamlet-normal-use-audit-tests`: 185 场景, 分组
  23/2/79/81.
- Mix 调用 Quint/Rust 作小预算诊断: 原 step 的四组各 200 条, 正常环境两组各 200 条, max-steps=100, seed=42, threads=2.
  共 1,200 条, 未观察到 commandSafety 违规. 这是覆盖诊断, 不替代既有 Q77 全量验证或构成穷尽证明.

**原 step 的覆盖偏斜:** 从 init 出发的严格、允许重复、资源排除三个实例, 本次各 200 条均见 Cancelled,
成功/失败/Waiting 为零. 因而这些通过轨迹不能单独确认正常执行闭环.
从合法 runningInit 运行原 step, 成功 13、失败 2、Waiting 68; 授权/调用在这个前缀中已成立, 不算新探索覆盖.
该次使用 `--init runningInit --step step`. 日志位于 `/tmp/beamlet-normal-use-audit-smoke`.

**正常环境审查:** 临时 `/tmp/beamlet-normal-use-audit.qnt` 调用原动作, 不请求取消、不引入故障/丢包/时钟跳变,
不调用查询或治理; 只在已知失败时提出替代, 仍经过原 canReplace. 使用 `--init init --step normalStep`.
Closed 后的显式 terminalObservation 仅保持终态以延长观察, 不给 Open 添兜底空转, 不代表实现了结果读取 API.

| 环境 (各 200 条) | 成功 | 失败 | 曾 Waiting | 已接持久化确认 | 替代 | 替代后成功 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 不接受重复风险 | 90 | 110 | 161 | 200 | 0 | 0 |
| 明确接受重复风险 | 119 | 81 | 163 | 200 | 25 | 12 |

两组的领取、授权、真实调用、资源完成、Resolved 均达到 200. 列可重叠, 不是事件次数或成功率承诺; 正常环境不含原 Worker
释放后的无查询回调. 第二组重试不证明幂等, 第一组不重试也不是死动作缺陷. 最终日志/参数位于
`/tmp/beamlet-normal-use-audit-healthy`; 临时入口初次绝对导入路径加载失败, 改为相对路径后类型/运行通过,
该加载错误不算安全反例. 现有 60 个反例此次未重跑, 继续以 Q77 留存结果为基线.

## 4. 模型纪律检查

- 通过: 70 个 .qnt 均不超过 200 行, 导入可解析且无环, 正常根入口不导入测试/变异.
- 通过: 五组状态初始化; 核心直接动作的 frame 完整, wrapper 复用子动作; 原 step 包含核心主要动作,
  扩展入口另行组合协调/治理; 类型化阶段/结果、无序消息与纯更新分离.
- 通过: Outcome 唯一/不可变、启动先后、存储后确认等不是单纯类型恒真性质; 场景有正向可达路径和禁止转换检查.
- 警告: 独立动作/里程碑见证存在, 但总抽样次数不是逐动作覆盖率; 初始取消偏斜需要单独的正常 profile/正向场景持续检查.
- 警告: init 假定持久化的 Open Intent 已建立, 权威转换理想化原子, 查询输入可信, 外部完成按模型契约生成.
  无公平性/Liveness 证明; 可达的正常路径不保证每种调度都会终结. 字符串 marks 仅观察标签, 不作为执行守卫.

## 5. 建议先补正常闭环, 再考虑结构收敛

1. 补独立可信回调的最小抽象、启动前持久关联见证, 以及无查询 Pending 释放 Worker 后完成的场景.
2. 用 opaque 定义/结果值表达相等与冲突, 补稳定提交身份、Closed 复用原业务结果; 不提前确定 codec/SQL 字段.
3. 表达使用到的 Handler 条件/稳定幂等上下文, 对齐停止策略与失败接受原子路径. 只补正常支持方式,
   不建通用能力/权限注册框架.
4. 固化正常 profile 与逐项 SPEC -> 抽象 -> 场景/性质映射; 已确认项有对应验证, 工程边界另行登记;
   缺失正常能力不以“罕见故障”排除. 这些是补全建议, 不是已经实施或新增已批准细节.

特殊接管、全面迁移故障、Byzantine、零停机、外部 exactly-once 不作为当前验收目标;
治理扩展暂停增加, 既有约束/见证/回归资产保留. 本轮未修改仓库 .qnt、Mix 工具或实现 Runtime.
