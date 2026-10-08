# 核心模型超时诊断

当前结果支持：**开放组合的 SMT 求解成本过高，240 秒预算不足，增加到 900 秒仍不能完成 depth10；本次未发现新的安全性反例。** 独立完成的完整组合界限为 depth4，受限恢复界限为 depth14。不能由这些结果推断完整组合 depth10 正确，也不能由超时推断模型违反契约。

本轮使用未修改的 [model.qnt](model.qnt)、[composition.qnt](composition.qnt)、[small.qnt](small.qnt) 与 [recovery.qnt](recovery.qnt)。日志写入已使用原始字节流，中文 Java 输出没有再触发 `:no_translation`。历史证据及接口前提见[核心验证报告](verification-report.md)。

## 配置与实验结果

工具为 Quint 0.32.0、Apalache 0.56.1 / build70cdaf4、OpenJDK21。机器为16逻辑 CPU、约31 GiB内存。所有 BMC 使用各自的工作目录和专用端口，默认 `init` / `step`、`--random-transitions=false`、`--backend apalache`。

实验并发执行；恢复完成后才开始 small。下表是当前机器与并发负载下的实际墙钟时间，不是独占运行基准，也不能据此精确预测下一次需要的预算。时间包含包装器、编译与服务启动、后端类型检查及求解，不包含 Mix quick 阶段。

| 实验 | 范围 / 属性 | 请求深度 | 预算 / 实际秒数 | 结果 |
| --- | --- | ---: | --- | --- |
| composition depth4 | 双 Run、FIFO6，完整 safety，开放 step | 4 | 360 / 281.188 | `NoError`、exit0；独立完成 depth4 |
| composition depth5 | 同一双 Run、FIFO6，完整 safety，开放 step | 5 | 360 / 360.039 | exit124；State5 期间超时，无完成界限 |
| composition depth10 | 同一双 Run、FIFO6，完整 safety，开放 step | 10 | 900 / 900.038 | exit124；State6 期间超时，无完成界限 |
| small depth10 | 单 Run、FIFO4，完整 safety，同一开放 step | 10 | 600 / 600.044 | exit124；State7 期间超时，无完成界限 |
| C2 成本对照 | 双 Run、FIFO6，同一 init/step，仅 C2 | 10 | 600 / 600.062 | exit124；State7 期间超时；不是完整 safety 检查 |
| recovery depth14 | 单 Run、FIFO4，受限14转换，core safety / premises / rankDecreases | 14 | 180 / 145.525 | `NoError`、exit0；仅指定恢复调度完成 |
| composition 抽样 | 双 Run、FIFO6，完整 safety，开放 step，10,000条 | 200 | 600 / 415.077 | Rust、seed20261015，exit0，未发现抽样反例 |

`StateK` 仅表示进度，表中的超时项没有建立 depthK。depth4 的结论来自该独立命令的 `NoError`，不是从 depth10 超时日志推断所得。recovery 使用 `recovery.init/step`，其调度与开放 `composition.step` 不同；较深的受限路径通过不能补全开放组合安全性或一般活性。

## 为什么超时

### 后端在实际求解

延长预算后，完整组合从上一轮240秒的 State5 推进到了 State6；当前900秒尝试的最后未完成查询是 State6 的后端 VC25。没有出现模型语法/类型错误、序列化失败或内存耗尽。

进程采样显示 Java CPU 计数持续增加，各后端 RSS 约0.9–1.4 GiB。结束后所有本轮专用端口对应的后端进程均已清理。日志没有显示进程在等待工具输入或因为内存错误停止。

### 开放转换与断言都有成本

完整组合和 small 均被后端展开为22转换、42个初始验证条件；恢复投影为14转换、47个初始验证条件，但每一步只有指定调度的下一转换可执行。恢复能完成 depth14，而开放模型在更小深度耗尽预算，说明动作交错与符号状态规模比请求步数本身更能解释耗时。

在当前并发实验中，完整组合的后端类型检查约97–101秒，恢复约104秒。C2 对照约16秒，生成3个初始验证条件，但仍保留同一22转换并在600秒内未完成 depth10。因此完整属性集确实增加成本，单纯删减属性也没有消除转换编码和深层求解的成本。

完整组合900秒日志中，后端 VC25 的**已完成**查询累计约166.8秒，VC21约87.7秒，另外还有转换编码、可执行性检查、其他验证条件及最终被截止的查询。这些序号属于生成后的后端条件，不能直接当作 C1–C6 编号，也不能把其高耗时解释为违例。

### 编码规模与待验证的优化方向

Quint 的完整组合 flattened JSON 约34.09 MB，其中模块表达式约0.38 MB，lookup table、types、effects 合计约33.71 MB。这是前端中间产物大小，不能直接当作 SMT 公式大小，也不能单凭它断言某个结构就是超时根因。

源码中值得进一步测量的成本来源包括：

- `Prior` 在每个动作保留相关 inbox 和完整 sourceBoundaries；稳定边界历史同时存在于当前状态及前态快照。
- 输入保留、原子消费与边界保留使用序列索引、`forall`、记录比较，结果归约还统计 Reply 序列。
- 开放 step 同时容纳求值、业务提交、控制、故障、恢复及分支；部分 nondet 参数在若干分支中不被使用。

这些结构表达的是实际契约。优化应先保留状态投影与可达转换的对应关系，再比较后端成本；本次未截断历史、删除前态事实、弱化完整 safety 或更改业务动作。只检查 C2 是明确的成本实验，不是优化后的完整模型。

`epoch` 和 `issued` 等整数可随控制/恢复动作继续增长；模型不是无深度限制的有限状态图。但本轮使用固定深度 BMC，存在无限长度行为不意味着后端在等待业务完成。

### 全局死锁与业务等待

`availability` 可切换 `writes`，并且包含在开放 `step` 中；具体实例的 Run0 和 owner 域均非空。因此开放模型保持全局可执行转换。这个事实不建立业务进度：暂停、权威不可用、身份或队列耗尽、unknown 等待恢复许可仍可阻止业务推进。恢复结果只覆盖显式前提与指定调度。

## 深度200抽样覆盖

本轮 Rust 求值411.237秒，外层耗时415.077秒，参数 seed20261015，复现 seed `0x94e439a`。完整 safety 未在这10,000条抽样轨迹中出现反例，所有请求目标均有正计数。

| witness | 到达轨迹数 |
| --- | ---: |
| intentWitness | 4687 |
| entryWitness | 138 |
| unknownWitness | 276 |
| recoveryWitness | 139 |
| consumedWitness | 30 |
| recoveryConsumedWitness | 4 |
| branchWorkWitness | 2530 |
| inconclusiveWitness | 19 |
| failedUnknownWitness | 20 |
| failedReplyWitness | 34 |

消费与恢复消费仍稀疏。抽样无反例不证明所有可达状态正确，目标到达不证明必然进度。本轮同时改变了深度与 seed，不能把相对旧抽样的计数变化只归因于深度。

## 复现

从仓库根目录直接调用 Quint 与系统 GNU timeout。以下保持原始串行求解配置；端口须专用，重新执行会产生新的结果和工具原始产物，实际耗时可能不同：

```sh
timeout --kill-after=5s 360s quint verify spec/quint/core/composition.qnt --invariant safety --max-steps 4 --server-endpoint localhost:18849 --verbosity 2
timeout --kill-after=5s 360s quint verify spec/quint/core/composition.qnt --invariant safety --max-steps 5 --server-endpoint localhost:18845 --verbosity 2
timeout --kill-after=5s 900s quint verify spec/quint/core/composition.qnt --invariant safety --max-steps 10 --server-endpoint localhost:18844 --verbosity 2
timeout --kill-after=5s 600s quint verify spec/quint/core/small.qnt --invariant safety --max-steps 10 --server-endpoint localhost:18847 --verbosity 2
timeout --kill-after=5s 180s quint verify spec/quint/core/recovery.qnt --invariant safety --max-steps 14 --server-endpoint localhost:18846 --verbosity 2
```

深度200抽样命令：

```sh
quint run spec/quint/core/composition.qnt --main composition \
  --invariant safety \
  --witnesses intentWitness entryWitness unknownWitness recoveryWitness \
    consumedWitness recoveryConsumedWitness branchWorkWitness \
    inconclusiveWitness failedUnknownWitness failedReplyWitness \
  --max-samples 10000 --max-steps 200 --seed 20261015 --verbosity 1
```

C2 成本对照在仓库根目录创建临时 `diagnostic_c2.qnt`：

```quint
module diagnostic_c2 {
  import core(RUNS = Set(0, 1), QUEUE_LIMIT = 6) as C from "./spec/quint/core/model"
  action init = C::init
  action step = C::step
  val safety = C::C2
}
```

然后从仓库根目录运行：

```sh
timeout --kill-after=5s 600s quint verify diagnostic_c2.qnt --main diagnostic_c2 --invariant safety --max-steps 10 --server-endpoint localhost:18848 --verbosity 2
```

本轮原始日志、计划、逐项结果和进程采样仅本地保存在 `/tmp/beamlet-quint-timeout-study-a01ajm7k`，不纳入 Git。新检出可依据上述配置生成自己的日志。

## 下一步判断

当前没有证据要求修改架构契约来“消除超时”。继续提高预算可能推进检查，但尚不能给出完成 depth10 所需预算。优先建立语义保持的编码成本实验，分别测量前态历史/序列比较、非确定参数展开及属性分组，再重新运行完整 safety；任何较小实例、单属性或受限调度结果都应保持各自范围。
