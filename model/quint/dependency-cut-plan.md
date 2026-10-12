# 模型依赖切割计划与执行记录

状态: 第一阶段核心独立已执行. 正常使用补全后, 按本轮请求建立 beamletExecution 并迁移首版执行/正常入口;
原组合模型保留, 命令和治理内部尚未进一步拆分. 实际验证与资产归属见 [执行核心覆盖](execution-core-coverage.md).
首版仍对无法安全解决的 Unknown/冲突保持 Open、提供事实读取, 后置人工裁定.

## 1. 已处理的耦合

| 原耦合 | 实际切分 | 保留约束 |
| --- | --- | --- |
| 大 Ledger/Message/ExternalState 包含决定、命令/拒绝、规则与观察 | `base/execution_state.qnt` 单独拥有五组执行状态; `base/state.qnt` 保留组合账本 | 核心没有治理字段, 不是填空列表模拟隔离 |
| lease/报告更新直接推进判断版本 | `execution_leases` / `execution_reports` 提供共享纯更新, 原 logic adapters 再 advanceJudgment | 组合参考仍验证审查版本与历史变化链 |
| Worker 计算耦合原大状态 | `execution_worker_values` 共享纯 Worker/资源计算, 两种 transport 类型各自适配 | incarnation、原 grant、实际调用和回执性质保留 |
| 原始证据与处置链混合解释 | `execution_evidence` 只解释原始证据/风险; 原 dispositions 继续解释明确协调 | 核心原冲突与未解释旧成功仍阻塞相应终结 |
| 普通结果和旧结果采用共用资格路径 | `execution_outcomes` 只保留普通结果; 原 outcomes 保留 adoptedResultEligible | 两者都保留 Outcome 唯一/不可变、Open 和来源风险守卫 |
| recovery 解释协调消息和处置 | `execution_recovery` 只解释执行消息与原始知识 | 到期/Unknown/NotFound 不单独授权重试 |
| 核心入口无条件导入治理动作/性质 | 新 beamletExecution + normal/recovery 为首版; beamletCore 留作组合参考 | 旧治理动作/性质与组合检查不删除 |
| 冲突历史性质混在协调文件 | 独立 execution properties 保留原始矛盾/结果值冲突与提交时阻塞检查 | 迟到冲突保留, 不追溯改写 Outcome; Cancelled 独立 |

目标方向仍为治理扩展 -> 协调命令 -> 执行安全核心. 本阶段完成核心可独立理解/执行,
没有把现有命令/治理重新包装成三个 Runtime 引擎, 也没有引入调用方自报的“已批准”放行通道.

## 2. seam 与共享方式

`base/execution_types` / `execution_values` 不拥有 protocol var, 提供共同领域类型、九个参数和不可变默认值.
共享纯 lease/report/Worker 逻辑使用 Quint 推断的开放 record, 保留调用方附加的扩展字段;
组合 adapter 显式维护判断版本, 首版无需知道 Decision/注册表/取代链.

相同 AuditKind 词汇保留两个扩展 History 标签以兼容组合记录, 核心不读取它们作守卫.
两种 ledger 的 frame wiring 和普通/协调结果解释仍各自明确; 通过共享规则、迁移资产及测试专用投影对照约束漂移.
不以重复代码行数或文件数量作为切分成败判断.

核心 Start/Commit/Retry、原结果与失效历史见证保留. Handler/停止见证只用于独立回查历史事实,
不成为运行守卫或公开持久化 schema. 没有 forceCommit 路径或隐式清除冲突/旧成功.

## 3. 迁移和组合检查

- 原 strictTests 23、fencedTests 2 通过修改原 fixture 依赖迁至独立核心; 原 run 名称/断言及路径保留.
- 原 normalUseTests 40 迁至独立核心, 加 9 个恢复/停止/旧窗口场景, 共 49.
- 执行九条 mutation 和 oldSuccessFailure 改依赖独立核心; 原七条 normal mutation 保留并补新窗口反例.
- repeatingTests 79、conflictTests 81 与其余 50 条 mutation 保留原组合模型.
- 新增五个无处置投影场景和三组 recoveryStep 投影抽样, 核对普通 guards/更新; 不外推为治理行为的等价证明.
- 保留原完整抽样组, 另加独立核心与五组恢复; 最新运行配置和结果见覆盖页.

`test/quint_structure_test.exs` 检查首版入口的传递依赖不含组合参考、测试/mutation 或治理类型,
以及所有 Quint 导入无环/每文件不超过 200 行. 参数仍在外层一次性绑定, 单实例 fixture 共享状态.

## 4. 后续边界

协调命令与治理账本继续共同保留, 暂无继续物理拆分的首版要求. 原授权、版本、取代/撤销约束仍约束未来功能,
Q78 撤销专属授权尚无新增验证. 不因功能后置降低既有安全规则.

多 Intent 完整执行、实际 SQL 并发/掉电、codec、签名和外部幂等前提转交工程符合性验证;
本轮已补三份 [首版工程契约](../spec/first-release-scope.md), 尚无 Runtime/真实 Adapter 实现结果.
抽样和局部投影检查不是穷尽正确性或全参数语义等价证明.

关联: [正常使用审查](normal-use-audit.md)、[正常闭环补全](normal-use-coverage.md)、
[最新验证](execution-core-coverage.md)、[反例记录](counterexamples.md).
