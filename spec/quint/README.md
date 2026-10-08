# 架构验证

当前主入口是[核心抽象](core/README.md)：C1–C6、显式接口前提、开放代表组合、确定性变异、固定 seed 抽样与实际 bounded 尝试。运行 `spec/quint/core/check.sh`，阅读[核心报告](core/verification-report.md)了解来源绑定结果和限制。核心是新抽象，不是大型模型的等价优化或证明。

用户的核心设计范围取代了原来的全文穷举覆盖目标。本目录其余模型与下文属于**历史/补充探索**；旧结果只适用于原哈希，不是当前核心验收清单，核心验收不关闭它们的未完成界限和缺口。

所有验证证据（包括 compact pack、元数据、日志、哈希记录、原模型/probe/ITF 副本）都只保留在本地、Git 忽略。`spec/quint/evidence/` 与 `spec/quint/core/evidence/` 都不提交。保留是为了审计和复现，不代表加入 Git。新检出读取人工[报告](verification-report.md)、[覆盖审计](coverage.md)与源码，并运行命令产生自己的本地证据；不能检查未提交的旧日志。

<a id="historical-detailed-exploration"></a>

## 历史详细探索

[architecture.qnt](architecture.qnt)把[架构契约](../architecture/index.md)组合为一个状态机：输入/授权、权威、求值/提交、控制器/Scope/提供者、主体进入/观测、FIFO、生命周期、历史 fork/import 共同交错。[types.qnt](types.qnt)提供封闭变体和完整 map 域，测试独立存放，没有把各组件独立状态机当成组合证据。

[reference.qnt](reference.qnt)投影输入、不可变意图、授权、实际进入、终局选择、输入处置与派生。`allowed(before, after)` 独立检查保留事实、合法执行、FIFO 原子提交与选定前缀来源；本地转换可不改变投影。没有无条件 stutter。

```sh
spec/quint/check.sh quick      # 全部类型检查与确定性/负控测试
spec/quint/check.sh simulate   # quick 加三组10,000条固定 seed 抽样
spec/quint/check.sh verify     # 组合与条件恢复的实际 bounded 尝试
spec/quint/check.sh all        # 默认执行全部
```

历史执行器使用现有 Quint0.32.0、随附 Apalache0.56.1 / OpenJDK21，默认输出到 `/tmp/beamlet-quint-check.*`。`QUINT_LOG_DIR` 可指定本地目录；`QUINT_VERIFY_TIMEOUT` 默认600秒。违例、超时或任何 witness 为零都返回非零，各独立检查仍继续；不能把单项模拟 exit0 当作 `all` 通过。

| 配置 | Run / Effect / Attempt | FIFO | init / step | 用途 |
| --- | --- | --- | --- | --- |
| architectureSmall | 1 Run、1 Effect、2 Attempt | 8 | init / step | 开发诊断 |
| architectureAnalysis | 2 Run、每 Run 2 Effect、每 Effect 3 Attempt、3主体实例 | 每 Run12 | init / step | 历史完整抽样10,000条/depth100/seed20261007 |
| architectureBounded | 2 Run、每 Run1 Effect、每 Effect2 Attempt、3主体实例 | 每 Run4 | init / step | 缩小域的完整组合，请求 depth10 |
| architectureRecoveryAnalysis | 扩展完整域 | 12 | recoveryInit / step | 从可达 unknown fixture 抽样10,000条/depth100/seed20261008 |
| architectureProgressAnalysis | 扩展完整域 | 12 | progressInit / progressStep | 条件确定调度10,000条/depth40/seed20261009 |

所有常量均实例化，ID 不回绕/重用。初始仅 Run0，Run1 可由 StartRun 或稳定前缀创建一次；Effect/Attempt 具有有限新槽位。死亡实例不复活。提供者代次与修订单调，探索深度限定范围。扩展命令键0–31（bounded 为0–9）、外部输入键每 Run0–7、观测键在权威域0–7。容量和新槽位耗尽是抽象限制，不是生产生命周期。

finished/failed、waiting 空队列、写入/资源不可用、暂停和 unknown 无恢复权限是合法等待。`G08` 区分有用协议动作与故障/控制/环境变化，只是有限域分类，不是无条件活性证明。

条件调度从与确定测试相同的 input/evaluate/intent/admit/enter/失联/unknown 前缀开始，假设权威与操作权限恢复、active/open、兼容可用提供者、活替代主体、显式 repeat、无新输入/故障，以及后续协议动作得到调度。rank 经 repeat、admit、enter、complete、observe、过时通知处置、evaluate、commit 八转换递减，消费后停止。10,000条同一路径不建立公平性；正常 `step` 保留任意故障、控制与竞争。

全局断言为 G01 保留提交事实、G02 合法执行、G03 知识/结果、G04 输入顺序/业务原子提交、G05 生命周期、G06 派生/权限隔离、G07 模型依赖边界、G08 进度分类。`architectureSafety` 合取它们与 reference；`modelCheckSafety` 直接别名，旧整数 truth indicator 已删除。

单个线性化持久权威是前提，可用性只表示接口访问，不验证 Ra/fsync/quorum/分区/磁盘。注册定义/提供者、观测真实性与兼容声明可信。应用状态为不透明整数与非确定候选返回，过近似合法 Definition；不包含 Agent 操作分支。Scope、资源、角色等只是有界语义，不等于真实部署、安全或 provider 图验证。

所有模型命令具有不可变 envelope：原 revision/epoch/cursor、意图/绑定、分支边界、裁定来源/证据/载荷。先授权再查回执，同键同载荷返回原回执，先于当前生命周期/写入条件。input/observation 独立冲突表；每个新命令历史只增加一次，原键重试不增加。共同 `step` 将权威操作通过该协议；本地 evaluate/entry/complete/故障仍分开。

<a id="historical-detailed-suite-fidelity-checkpoint"></a>

## 历史保真修复检查点

旧观察键缺失原绑定字段、恢复复用旧主体和终态控制盲点的 gap probe，已经改为要求拒绝/检测的回归。原始坏行为日志仍仅本地保留。正常观察键比较包含 Attempt/owner/provider/resource/generation/domain/intent/payload。恢复排除相关 unknown 工作的旧实例；重连保持原实例与标记，可以原 Attempt 重投，不使其成为新的恢复主体。

失败声明从 evaluation 捕获到不可变 Effect，局部失败保留 unknown，不能清除较早未知。独立控制拒绝终态 mode/epoch 变异；分支必须来自前态保留稳定边界，保留 state/Definition/result/完成输入与结果载荷，新身份、游标、队列、纪元、Attempt 与许可独立检查。没有以标记布尔值替代来源证明。

`combinedInterleavingTest` 使用真实 envelope/receipt 执行41转换、26新 command ID，含恢复/settlement/迟到观测、消费与分支工作。`recoveryFixtureEnvelopeTest` 匹配四命令前缀；条件八转换调度结束时保留九命令。`protocol_test.qnt` 有13协议测试；九负控覆盖 guard/update 绕过与独立断言，部分手工事实损坏不等于可达转换变异。

进一步建模 StartRun/初始 ready/receipt、两个不透明注册 Definition、interaction/compute/execute/authority 角色、两层 Scope 选择/隔离、精确资源身份与权限、consistent inspect/export/resource-use、完成事件/结果载荷历史。`formal_test.qnt` 检查两种 Definition 至 Finish/finished import、Scope fallback/隔离、绑定变化后的预检、资源拒绝、角色/写入与授权。提供者清理图、真实代码/模式/ETF/平台/Ra 仍未验证。

扩展测试容量32容纳41转换路径；bounded 配置10命令键可支撑其最多十步新命令探索，但不是完整路径可容纳或界限完成证据。G08 检查所有 guarded 返回变体及真实阻塞；无 blanket permission/queue fallback。新 Definition 暴露的 continue/finish usefulEnabled 遗漏已修复。

历史最后 checkpoint 为九项 typecheck、97确定测试通过（54场景、13协议、9原变异、8形式维度、1 envelope scheduler、12 review 回归/变异）。模型哈希和旧抽样的来源对应见[历史报告](verification-report.md)。保真修复后没有新的最终10,000抽样或 backend/compile；完整组合 depth1 曾在 JSON serializer 失败，depth10 未完成。旧抽样不验证后来的模型依赖，核心结果不清除这些历史缺口。

```sh
quint test spec/quint/architecture_test.qnt --main architecture_test \
  --match combinedInterleavingTest --backend typescript --seed 20261007 \
  --out-itf '/tmp/beamlet_{test}_{seq}.itf.json'
```

此复现命令本轮未执行。长 `then`/`expect` 曾触发 Rust JSON recursion limit，确定测试使用正式 TypeScript evaluator，模拟使用 Rust。witness 证明可达，抽样无反例不是穷举，超时不是任何已完成较小界限。

Mnesia / disk_log 仅保留在 ADR-007 的替代解释，本轮不新增依赖/后端/运行时。Ra 仍是唯一条件候选。
