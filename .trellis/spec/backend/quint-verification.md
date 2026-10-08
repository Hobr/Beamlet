# Quint 验证规范

## 范围与文档目的

使用能暴露错误答案的最小模型回答架构问题。主套件为 `spec/quint/core/`，详细探索套件为补充。增加状态前说明来源对应、接口前提与非目标，保留架构/ADR 历史。技术设计处置、模型证据和运行时采用验证分别记录，模型检查本身不提升实现状态。

`spec/` 面向所有开发者，默认使用中文。保留契约、术语、选择理由、来源对应、模型范围、命令、实际结果与限制；不放会话角色、流程标识、用户指令复述、交接验收、索引事件或一次性整理日记。代码标识符、命令、API 与原始日志保持原文。验证执行器不生成或校验源文件摘要，也不建立替代源指纹机制。

## 命令与执行器

从仓库根目录执行：

```sh
mix quint.quick
mix quint.simulate
CORE_VERIFY_TIMEOUT=900 mix quint.verify
mix quint
mix quint.supplemental quick
```

`quick` 类型检查并运行确定性测试，`simulate` 加代表组合抽样，`verify` 调用正式有界后端，`all` 包含三者。`mix quint` 默认核心 all；补充显式选择 quick/simulate/verify/all，其 verify 保留不先 quick 的行为。Mix 薄别名调用单一 `spec/quint/check.exs`，直接入口为 `elixir spec/quint/check.exs quick`。

`Beamlet.Quint.main(argv, root \\ repository_root)` 返回 `0 | 1 | 2`，直接 Elixir CLI 保留该退出码。Mix 别名将任何非零结果通过 `Mix.raise` 转为 CLI exit1，并在错误消息中保留执行器原返回码。

`CORE_LOG_DIR` / `QUINT_LOG_DIR` 指定 `/tmp` 或被忽略 evidence 树内的空目录，默认输出到 `/tmp`。目录独占，防止并发共用或覆盖。`CORE_VERIFY_TIMEOUT` 为正整数秒，默认240；`CORE_SERVER_PORT` 为专用合法端口，默认8842。补充预算默认600秒，接受正 GNU duration。

命令使用 executable 和独立 argv，不能拼接 shell。保存命令、工具版本、BEAM 环境、域、逐项日志、退出与耗时。请求 witness 与 validator 共用列表，每项必须存在且为正；失败后继续后续检查并聚合非零。

子进程 stdout/stderr 以原始字节保存：`File.open!(path, [:write], ...)` 配合 `IO.binstream(io, :line)`。不要在默认文件设备上使用 `IO.stream(io, :line)`：设备编码为 `:latin1`，中文 locale 下 Java 输出的“10月”“下午”“警告”等 Unicode 文本会触发 `:no_translation`，使日志写入失败并丢失真实后端退出码。两套入口的回归须注入 Unicode stdout/stderr，检查完整字节保留，以及 exit0/非零退出码和聚合结果。

| 条件 | 行为 |
| --- | --- |
| 所选检查全部通过 | 执行器返回0 |
| 子命令非零或 witness 缺失/零值 | 保存逐项日志、继续后续检查，聚合返回1 |
| 找不到工具 | 该项 exit127，错误进入日志，聚合失败 |
| 模式/套件/预算/端口无效，或输出目录不允许/非空 | 返回2，保存配置错误，不覆盖已有日志 |
| 核心有界检查超时 | 该项 exit124，回收自己的进程组，聚合失败；界限无结论 |

核心 Python 包装器管理 POSIX 专属进程组和截止清理，仅保证该组内的后代。核心与补充每条 backend 命令都在本次日志目录内独立工作目录执行，通过源码符号链接保留相对 argv，新 `_apalache-out/` 留在该目录。补充 GNU timeout 不保证清理另起会话的后代。checkpoint 只读该次产物，缺失明确记录，不从共享目录挑选其他运行的最新日志。

## 契约与抽象

- 核心假设原子持久权威、认证/有效/幂等命令、兼容且真实的提供者观测和可移植值，检查其架构使用；实际实现内部属于 I1–I4。
- 故障或控制可介入时，保留 evaluation/commit、admission/entry、completion/recording、result/consumption 的独立转换。
- unknown 是权威知识。后来的失败或 not_executed 不清除另一 Attempt 的未决工作。局部失败即使 knowledge 为 Recorded，仍可逻辑未决。
- 正常失败选择读取全部保留观测与其他 admitted/未决工作，不依赖 Attempt 顺序。本地完成未记录不是权威知识。未执行证明只解除自己的 Attempt；阻碍独立解除后，保留逻辑失败可能变为充分。终局前有效成功仍充分，已有终局结果与唯一回复不被覆盖。
- 同一 Attempt 已有有效确定原观测后，迟到监视器失联报告不得因 observation_id 不同而覆盖它、重开已解除未知或追加通知。局部失败与另一个 Attempt 的失联独立处理，见[证据优先规则](../../../spec/architecture/authority-and-recovery.md#monitor-evidence-order)。
- 用授权事实和观测含义区分 Executing/Uncertain 与主体资格。`core.unresolved(at: Attempt, e: Effect)` 和 `core.reduce(e: Effect, at: Attempt, other: Attempt)` 是实现 helper，不能用其返回值替代独立断言。
- 使用小记录/变量，每个 backend 入口只包含一个具体实例。Quint0.32.0 可能保留同一解析文件中未选实例的结构元数据，导致序列化膨胀。
- 每次结果记录实际命令、工具版本、模型范围、init/step/property、depth、seed、数量、预算、退出与耗时。模型依赖改变后重做受影响检查，文档整理不产生新的模型证据。

## 证据强度与回归

| 证据 | 允许的结论 |
| --- | --- |
| typecheck/test | 类型或显式路径断言通过 |
| witness 正计数 | 记录配置下目标可达 |
| 抽样无违例 | 给定数量、深度与 seed 内未找到反例，非穷举证明 |
| BMC 完成 | 在该模型域与完成界限内无违例 |
| 超时/序列化/后端失败 | 无结论，不能声称请求界限完成 |
| 正在检查 StateK | 仅进度，不是 depthK 完成证明 |

条件调度列明前提。严格递减 rank 与固定调度 bounded check 只覆盖指定调度，恢复 witness 不证明一般活性。有限身份/队列耗尽与稀疏消费必须报告，不用无条件 stutter、循环 blocked 分类或无关权限 fallback 掩盖停滞。

断言独立于 guard，读取最小真实前态。适用时加入无授权/继承主体进入、旧提案、双终局回复、repeat 重用、跳 FIFO/部分提交及分支继承权限的检测变异。故意展示坏行为的通过 probe 不计为修复通过。

证据归约回归覆盖：另一 admitted Attempt 未进入或本地完成未记录、终局前晚成功、非执行使保留失败充分、局部失败仍未决，以及遗漏 admitted blocker 的检测变异。failed 保留原授权与迟到回复，拒绝业务恢复、新授权、settle 和 repeat；未处理回复不记为 consumed。

监视器回归区分 guard/事实与排队报告投递。`lose(r, a)` 只接受 Admitted；在 nonexecution/局部失败后拒绝 lose，不执行 distinct-ID 载荷或持久化其审计。真实延迟报告、验证与审计归属 I2/I3/S4。外部 API 引用固定到实际检查版本，源码段落不是采用测试。

抽样 positivity validator 检查每个请求目标。十项核心目标的20个 missing/zero 注入案例必须聚合失败，无关目标正计数不能替代缺项。

## 执行器验证

执行器改变后运行 `mix format --check-formatted`、`mix compile --warnings-as-errors`、`mix test` 和真实 `mix quint.quick`。集成回归覆盖两套模式的 argv/seed、错误聚合、witness 缺失/零值、特殊路径、日志独占、配置错误，以及包装器超时后的产物隔离、所属进程停止与无关进程保留。假工具只验证编排，不计模型抽样/BMC。

仅注释/空白变化可用语法、格式和语法树等同性代替行为回归：Python 比较去位置属性的 AST 与非注释 token，Elixir 解析后递归去节点位置元数据。若有可执行行或依赖变化，仍执行完整检查。

正例：`admit replacement -> record original logical failure` 保持 NoResult/Executing；替代主体本地成功仍不改变权威知识，记录成功后才出现一个 Ok/Reply。反例：信任动作写入的 valid 字段，或用新 Attempt 的未执行证明清除旧 unknown。

## 本地日志与可读交付

全部验证捕获只在本地保留，两个完整 evidence 目录受根目录忽略规则覆盖。保留原始日志、反例和模型/测试副本字节，不翻译或规范化历史捕获。人工报告/README/coverage 必须自行说明结果、配置、限制和复现命令，必需 Markdown 链接指向可提交文档或源码，不依赖忽略目录。

检查保存条件时，直接比较工作树字节与完整索引记录；已有暂存内容保持。`git diff --check` 只检查其对应差异，差异为空不表示文件没有空白问题。日志整理不要求重复未改变模型的抽样/BMC。

Ra 仍为 ADR-007 条件候选，Mnesia/disk_log 是替代比较；实际存储、提供者、ETF、资源和平台支持须满足相应契约的实现验证义务。
