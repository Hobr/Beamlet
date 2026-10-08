# 架构验证

当前主入口是[核心抽象](core/README.md)：C1–C6、显式接口前提、开放代表组合、确定性变异、固定 seed 抽样与实际 bounded 尝试。运行 `mix quint`，阅读[核心报告](core/verification-report.md)了解来源绑定结果和限制。核心是新抽象，不是大型模型的等价优化或证明。

本目录其余模型用于补充探索，展开 command/receipt、Scope、资源与角色等有界维度。已有结果须按模型版本解释，详见[补充报告](verification-report.md)与[覆盖映射](coverage.md)。核心 C1–C6 结果不能补全详细模型的未完成界限。

运行日志仅保存在本地，Git 不包含原始捕获；新检出可以阅读源码、结果摘要与命令，并生成自己的日志。

<a id="detailed-model"></a>

## 详细模型

[architecture.qnt](architecture.qnt)把[架构契约](../architecture/index.md)组合为一个状态机：输入/授权、权威、求值/提交、控制器/Scope/提供者、主体进入/观测、FIFO、生命周期、历史 fork/import 共同交错。[types.qnt](types.qnt)提供封闭变体和完整 map 域，测试独立存放，没有把各组件独立状态机当成组合证据。

[reference.qnt](reference.qnt)投影输入、不可变意图、授权、实际进入、终局选择、输入处置与派生。`allowed(before, after)` 独立检查保留事实、合法执行、FIFO 原子提交与选定前缀来源；本地转换可不改变投影。没有无条件 stutter。

```sh
mix quint.supplemental quick      # 全部类型检查与确定性/负控测试
mix quint.supplemental simulate   # quick 加三组10,000条固定 seed 抽样
mix quint.supplemental verify     # 组合与条件恢复的实际 bounded 尝试
mix quint.supplemental all        # 默认执行全部
```

补充与核心共用[薄命令入口](check.exs)，使用 Quint0.32.0 / 随附 Apalache0.56.1 / Java21。`--cores N` 指定 SMT 线程数，默认8；`--timeout N` 指定每次后端检查的等待秒数，默认0（不限时），如 `mix quint.supplemental verify --cores 4 --timeout 600`。不使用 `QUINT_LOG_DIR` / `QUINT_VERIFY_TIMEOUT` 环境变量。`quick` 运行全部补充类型检查与确定测试，`simulate` 先 quick 再三组抽样；补充 `verify` 不先 quick。

输出直接显示在终端。违例、工具/配置失败、超时或任何请求 witness 缺失/为零都返回非零，首个失败即停止；不能把单项模拟 exit0 当作 `all` 通过。

两套 backend 调用共用系统 GNU `timeout`。执行器只临时生成线程配置，不维护自定义日志和检查点；Apalache 原始产物保留在被忽略的 `_apalache-out/`。进度不建立完成界限，补充成功也不清除核心无结论。

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

<a id="model-regressions"></a>

## 详细模型与回归范围

旧观察键缺失原绑定字段、恢复复用旧主体和终态控制盲点的 gap probe，已经改为要求拒绝/检测的回归。原始坏行为日志仍仅本地保留。正常观察键比较包含 Attempt/owner/provider/resource/generation/domain/intent/payload。恢复排除相关 unknown 工作的旧实例；重连保持原实例与标记，可以原 Attempt 重投，不使其成为新的恢复主体。

失败声明从 evaluation 捕获到不可变 Effect，局部失败保留 unknown，不能清除较早未知。独立控制拒绝终态 mode/epoch 变异；分支必须来自前态保留稳定边界，保留 state/Definition/result/完成输入与结果载荷，新身份、游标、队列、纪元、Attempt 与许可独立检查。没有以标记布尔值替代来源证明。

`combinedInterleavingTest` 使用真实 envelope/receipt 执行41转换、26新 command ID，含恢复/settlement/迟到观测、消费与分支工作。`recoveryFixtureEnvelopeTest` 匹配四命令前缀；条件八转换调度结束时保留九命令。`protocol_test.qnt` 有13协议测试；九负控覆盖 guard/update 绕过与独立断言，部分手工事实损坏不等于可达转换变异。

进一步建模 StartRun/初始 ready/receipt、两个不透明注册 Definition、interaction/compute/execute/authority 角色、两层 Scope 选择/隔离、精确资源身份与权限、consistent inspect/export/resource-use、完成事件/结果载荷历史。`formal_test.qnt` 检查两种 Definition 至 Finish/finished import、Scope fallback/隔离、绑定变化后的预检、资源拒绝、角色/写入与授权。提供者清理图、真实代码/模式/ETF/平台/Ra 仍未验证。

扩展测试容量32容纳41转换路径；bounded 配置10命令键可支撑其最多十步新命令探索，但不是完整路径可容纳或界限完成证据。G08 检查所有 guarded 返回变体及真实阻塞；无 blanket permission/queue fallback。新 Definition 暴露的 continue/finish usefulEnabled 遗漏已修复。

详细模型最近的检查结果为九项 typecheck、97确定测试通过（54场景、13协议、9原变异、8形式维度、1 envelope scheduler、12 review 回归/变异）。各版本结果与旧抽样的适用范围见[历史报告](verification-report.md)。保真修复后没有新的最终10,000抽样或 backend/compile；完整组合 depth1 曾在 JSON serializer 失败，depth10 未完成。旧抽样不验证后来的模型依赖，核心结果不清除这些历史缺口。

```sh
quint test spec/quint/architecture_test.qnt --main architecture_test \
  --match combinedInterleavingTest --backend typescript --seed 20261007 \
  --out-itf '/tmp/beamlet_{test}_{seq}.itf.json'
```

此命令用于复现确定性路径。长 `then`/`expect` 曾触发 Rust JSON recursion limit，确定测试使用正式 TypeScript evaluator，模拟使用 Rust。witness 证明可达，抽样无反例不是穷举，超时不是任何已完成较小界限。

存储实现的候选条件与替代方案见[ADR-007](../architecture/decisions.md#adr-007-review)。
