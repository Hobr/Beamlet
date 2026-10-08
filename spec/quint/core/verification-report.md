# 核心验证报告

核心模型检查 [C1–C6 架构问题](README.md#questions-and-correspondence)：提交事实保留、原主体单次进入、不确定性与恢复、输入原子消费、控制封闭和稳定分支。[ADR-008 技术设计](../../architecture/protocol-review-2026-10-08.md#disposition)已接受；ADR-007 中 Ra 保持条件候选。**完整组合 depth10 尚无结论，I1–I4 运行时验证尚未执行。**

## 模型范围与已有结果

工具配置为 Quint 0.32.0、Apalache 0.56.1（build70cdaf4）、Java 21。代表组合实例化 Runs0/1、每 Run 一个 Effect、每 Effect 两个 Attempt、两个主体实例和 FIFO6；默认 `init` / `step` / `safety` 保留故障、控制及源/分支交错。恢复投影使用 Run0/FIFO4 和受限的14转换调度。

下表保留既有历史模型结果；执行器简化时没有重新运行抽样或有界后端。日志编码修复后的追加检查见[超时诊断](timeout-analysis.md)，其独立结果与这些历史耗时分别解释。

| 检查 | 配置与实际结果 | 允许的结论 |
| --- | --- | --- |
| 类型与确定性测试 | 六项 typecheck；core_test 的46项测试通过（28正例、18检测变异），TypeScript / seed20261014，exit0 | 类型与显式路径断言通过 |
| 条件恢复路径 | recovery_test；14转换逐步检查 safety、premises、严格递减 rank，最终 consumed/finished，exit0 | 指定条件下路径可达 |
| 代表组合路径 | combinedTest；25状态/24转换，含恢复、迟到观测与源/分支工作，exit0 | 跨边界路径可达 |
| 非空检查 | 默认 init 满足 safety，十个 witness 初始均为 false | 目标需要实际转换 |
| 代表组合抽样 | Rust / composition / 默认 init+step / safety；10,000条、depth60、seed参数20261014（复现0x35e178f）；exit0，无采样反例；求值78.280秒、管理耗时85.006秒 | 有限抽样未发现反例，非穷举证明 |
| 完整组合 BMC | 所有动作 / init+step / safety / random-transitions=false / depth10；预算240秒；240.054秒在 State5 超时，exit124 | 请求界限及任何较小界限均未建立 |
| 受限恢复 BMC | recovery.init/step/safety，包含 core safety、premises、rankDecreases；depth14 / random-transitions=false / 预算120秒；NoError、exit0；求值82.029秒、管理耗时90.008秒 | 仅在指定恢复调度与有限域内无违例 |

| 非初始 witness | 10,000条中的计数 |
| --- | ---: |
| intentWitness | 1791 |
| entryWitness | 139 |
| unknownWitness | 225 |
| recoveryWitness | 158 |
| consumedWitness | 5 |
| recoveryConsumedWitness | 1 |
| branchWorkWitness | 567 |
| inconclusiveWitness | 16 |
| failedUnknownWitness | 10 |
| failedReplyWitness | 5 |

十项均正，消费5次与同一 Run 的恢复消费1次仍稀疏。到达目标不表示必然进度。恢复调度要求可用权威、active 控制、合法步骤与 finish、兼容且活着并成功的替代主体、显式 repeat、足够容量、指定动作最终得到调度，以及无新增故障、控制或输入干扰；它不建立任意状态恢复或一般活性。

## 超时诊断补充

日志编码修复后，未修改核心模型而追加分层检查：完整双 Run / FIFO6 / 开放 step / safety 的独立 depth4 检查在281.188秒完成 `NoError`；depth5 在360秒超时，depth10 在900秒于 State6 超时。单 Run / FIFO4 的 depth10 和双 Run 仅 C2 的成本对照均在600秒于 State7 超时。后两者不能替代完整组合 safety。

受限恢复 depth14 在145.525秒完成 `NoError`。另一次10,000条 / depth200 / seed20261015抽样未发现反例，十项 witness 均正，消费30次、恢复消费4次；这些计数仍不建立一般活性。实验存在并发负载，耗时不是独占运行基准。

这些结果支持开放转换和状态/属性编码存在求解成本瓶颈；240秒预算不足，但提高到900秒仍未完成请求的 depth10。没有发现新的安全性反例，也不能据此宣布模型完全正确。具体参数、成本对照、覆盖计数与复现命令见[超时诊断](timeout-analysis.md)。本轮结果独立于下文记录的早期240/900秒尝试。

## 实质缺陷与修复

| 缺陷 | 原行为与检测 | 修复及对应义务 |
| --- | --- | --- |
| 保留失败观测未被归约 | 旧 Attempt unknown，恢复 Attempt 记录逻辑失败，旧 Attempt 后证明未执行；旧模型停在 NoResult/Dormant、无 Reply。要求 Error/Reply 的回归 exit1，坏行为诊断 exit0 | 正常 reducer 读取所有保留有效观测；未执行证明仅解除自己的 Attempt，已有逻辑失败在阻碍解除后可产生唯一 Error/Reply |
| 终局失败漏掉其他 admitted 工作 | Attempt0 unknown，repeat 授权 Attempt1，Attempt0 的失败在 Attempt1 仍 admitted 时提前选择 Error；随后有效成功也被旧终局挡住。要求 NoResult/Executing 的断言 exit1，13转换坏行为诊断 exit0 | 未进入、执行中及本地完成未记录的 admitted 工作均阻止失败选择；终局前有效成功仍充分。加入独立前态断言和漏掉 admitted blocker 的检测变异 |
| 恢复表排除首次合法进入 | 原实例尚未进入时，重复分发被误写成只能查询 | 原授权跨控制变更保留；同实例未进入时至多首次调用一次，已进入时只查询或重报 |
| witness 检查不完整 | 请求十项却只强制检查七项 | 请求与 validator 共用完整列表；每项缺失或零值均聚合失败，20个注入案例验证该行为 |
| 同一 Attempt 的迟到监视器规则不闭合 | 已验证 not_executed 后，另一 observation_id 的失联报告可能重开未知、追加通知 | [证据优先规则](../../architecture/authority-and-recovery.md#monitor-evidence-order)限定迟到报告只追加审计。三个模型回归检查确定事实后的 lose 拒绝、局部失败仍未决、另一 Attempt 独立失联 |

坏行为诊断通过只能说明旧缺陷可达，不能算修复通过。`Attempt.evidence`、本地 `actual` 与 `knowledge` 分开；`Recorded` 不等于逻辑已解决。独立属性读取前态授权与观测，不调用 reducer 或 guard 作证明。

监视器回归只检查事实和 guard，**没有投递不同 observation_id 的排队载荷，也没有验证其审计持久化**；真实行为归属 I2/I3/S4。失败声明在求值时捕获并固定，普通错误、超时或注册表变化不能赋予逻辑失败含义。

failed 保持封闭：无 resume、新 admit、commit、repeat 或 settle；原授权、unknown 与迟到观测保留，晚回复为 Unprocessed，不产生业务消费。稳定前缀是只读值，新分支使用新队列、身份与权限。完整技术取舍见[协议评审](../../architecture/protocol-review-2026-10-08.md)。

## 复现命令

常用入口为 `mix quint.quick`、`mix quint.simulate`、`mix quint.verify` 或 `mix quint`；模式、线程数与时间预算见[核心说明](README.md)。以下命令说明上述模型配置，再次执行会产生新的结果：

```sh
quint typecheck spec/quint/core/core_test.qnt
quint test spec/quint/core/core_test.qnt --main core_test --match '.*Test' --backend typescript --seed 20261014
quint test spec/quint/core/recovery_test.qnt --main recovery_test --backend typescript --seed 20261014
quint test spec/quint/core/core_test.qnt --main core_test --match combinedTest --backend typescript --seed 20261014 --out-itf '/tmp/combined_{test}_{seq}.itf.json'
quint run spec/quint/core/composition.qnt --main composition --invariant safety --witnesses intentWitness entryWitness unknownWitness recoveryWitness consumedWitness recoveryConsumedWitness branchWorkWitness inconclusiveWitness failedUnknownWitness failedReplyWitness --max-samples 10000 --max-steps 60 --seed 20261014 --verbosity 1
mix quint.verify --cores 1 --timeout 240
```

受限恢复可直接调用 Quint：

```sh
timeout --kill-after=5s 120s quint verify spec/quint/core/recovery.qnt \
  --main recovery --invariant safety --max-steps 14 --server-endpoint localhost:8843
```

运行日志仅保存在本地，Git 不包含原始捕获。新检出可以读取本报告与模型、执行命令生成日志，无法独立查看已有运行的原日志。模型依赖改变后须重新检查受影响的结果；文档整理不产生新的模型证据。

## 执行器检查与限制

[check.exs](../check.exs)只负责参数、Quint 命令调用和抽样 witness 正计数检查。输出显示在终端，首个失败即停止；时间预算使用系统 GNU `timeout`。Python 包装器、假 CLI 与自定义日志/检查点设施已移除。超时只说明预算耗尽，进度不能当作已完成界限。

当前简化入口通过格式、编译及3项参数/coverage 回归。真实核心 quick 的六项类型检查、恢复路径及46项核心确定测试通过，combinedTest 已包含在46项中。小模型检查验证线程配置可加载与限时返回124，不能当作核心组合 depth10 完成证据。

## 尚未验证的行为

I1–I4 仍需实际 Ra/磁盘/quorum、命令/授权/回执、进程/提供者/版本/资源和 codec/archive 故障测试。核心假设这些接口成立，只检查其架构使用；它不展开完整 command/receipt/observation/input 键表、DTO、错误优先级、审计载荷历史或绑定内部。

有限身份与 FIFO 不复用、不回绕，容量耗尽是抽象限制。早期模型的240秒及900秒完整组合尝试也分别在 State5、State6 超时，均未建立任何完成界限，且不能用于验证后续修复。[详细探索套件](../verification-report.md)的旧抽样、序列化失败与未完成界限另有范围限定。Ra 是条件候选，OTP29 / Elixir1.20 的 Ra 构建、平台支持、真实提供者符合性及有界解码资源防护尚未验证。
