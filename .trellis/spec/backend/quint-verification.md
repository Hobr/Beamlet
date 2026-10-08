# Quint 验证规范

## 范围与文档目的

使用能暴露错误答案的最小模型回答架构问题。主套件为 `spec/quint/core/`，详细探索套件为补充。增加状态前说明来源对应、接口前提与非目标，保留架构/ADR 历史。技术设计处置、模型证据和运行时采用验证分别记录，模型检查本身不提升实现状态。

`spec/` 面向所有开发者，默认使用中文。保留契约、术语、选择理由、来源对应、模型范围、命令、实际结果与限制；不放会话角色、流程标识、用户指令复述、交接验收、索引事件或一次性整理日记。代码标识符、命令、API 与原始日志保持原文。验证执行器不生成或校验源文件摘要，也不建立替代源指纹机制。

## 命令与执行器

从仓库根目录执行：

```sh
mix quint.quick
mix quint.simulate
mix quint.verify --timeout 900
mix quint --cores 16 --timeout 0
mix quint.supplemental quick
```

`quick` 类型检查并运行确定性测试，`simulate` 加抽样，`verify` 调用有界后端，`all` 包含三者。`mix quint` 默认核心 all；补充 verify 不先 quick。Mix 薄别名调用 `spec/quint/check.exs`，直接入口为 `elixir spec/quint/check.exs quick`。

两套入口共用 `--cores N`（正整数，默认8，Z3 SMT 线程数）与 `--timeout N`（非负整数秒，默认0，取消每次后端检查的截止）。参数校验在启动工具前完成。不使用 `CORE_*` / `QUINT_*` 环境变量配置验证。线程数不绑定具体 CPU 核心，也不保证固定倍数加速。

### 手动参数契约

1. **范围与触发**：Mix 别名与直接 Elixir 入口共用解析、命令生成和参数覆盖，修改任一入口时检查两者。
2. **签名**：`mix quint [quick|simulate|verify|all] [--suite core|supplemental] [--cores N] [--timeout N] [--max-samples N] [--max-steps N] [--seed N] [--verbosity N] [--n-threads N] [--match REGEX] [--server-endpoint HOST:PORT] [--help]`。
3. **契约**：`--max-samples` / `--seed` 用于 test/run；`--max-steps` 用于 run/verify；`--verbosity` 用于 test/run/verify；`--n-threads` 只用于 Rust run；`--match` 只用于 test；`--server-endpoint` 只用于 verify（Quint 默认 localhost:8822），可用不同本地端口隔离并行 Apalache 检查。用户值替换原默认值，每个 flag 只出现一次；未设置时保留场景原 seed、深度、筛选与数量。类型检查不接收这些选项。`all` 中覆盖值用于每个支持该选项的场景，verify 前置测试同样接收测试选项。完整默认值见[参数表](../../../spec/quint/core/README.md)。`--help` 显示帮助、返回0且不启动工具。
4. **校验与错误**：cores/max-samples/n-threads 必须为正整数；timeout/max-steps/seed 为非负整数；verbosity 为0–5，simulate/all 要求至少1以保留 witness 输出。server-endpoint 的主机名须为字母/数字/点，端口1–65535，与 Quint0.32 地址语法一致。未知参数、缺值、非法数值和模式在启动工具前抛出 `ArgumentError`，直接 CLI 返回2，Mix 返回1并报告 exit2。
5. **正常、默认与错误用例**：`mix quint.verify --max-steps 2 --timeout 60` 请求较小界限；无选项保留核心 depth10；`mix quint.simulate --verbosity 0` 在运行前失败。低抽样量/深度仍执行全部 witness 正计数校验，筛选测试通过只代表选中范围。
6. **必需测试**：检查核心/补充原默认值、用户值替换且无重复 flag、不支持选项的命令不收到该 flag、数值边界、帮助不启动工具、witness 缺失/零计数失败；真实 quick 与小界限调用确认工具接受 argv。
7. **错误与正确做法**：不要把用户 flag 直接追加到已有同名 flag 后，或无差别传给 typecheck；先按子命令支持集合替换已有值，再用独立 argv 执行，避免重复参数被 Quint 解析成数组。

命令使用独立 argv。类型检查、确定测试和后端进度通过 `IO.binstream(:stdio, :line)` 原样显示，避免 Unicode 编码转换；抽样输出在结束时显示并校验每个请求 witness 的正计数。首个失败即停止，保留子命令退出码；配置或工具启动异常返回2。Mix 将非零结果转为 CLI exit1，并保留原返回码。

不维护自定义证据目录、日志/耗时文件、运行清单或检查点。后端只需要临时 JSON 线程配置，调用结束即删除。使用系统 GNU `timeout --kill-after=5s` 控制每次后端调用，超时返回124并明确标记无结论。Quint 自己管理启动的 Apalache 服务；不维护 Python 进程管理包装器或假 CLI 脚本。Apalache 的原始 `_apalache-out/` 保持工具行为并由 Git 忽略。

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

诊断超时应保持模型、init/step/property 明确，分别增加预算、独立执行较小界限，并使用受限调度/较小实例/单属性作为成本对照。记录后端类型检查与求解阶段、实际退出码和并发负载；不能把不同范围的成功或较高 State 进度拼成完整界限，也不能把高耗时的生成 VC 直接判为契约违例。当前案例见[核心超时诊断](../../../spec/quint/core/timeout-analysis.md)。

条件调度列明前提。严格递减 rank 与固定调度 bounded check 只覆盖指定调度，恢复 witness 不证明一般活性。有限身份/队列耗尽与稀疏消费必须报告，不用无条件 stutter、循环 blocked 分类或无关权限 fallback 掩盖停滞。

断言独立于 guard，读取最小真实前态。适用时加入无授权/继承主体进入、旧提案、双终局回复、repeat 重用、跳 FIFO/部分提交及分支继承权限的检测变异。故意展示坏行为的通过 probe 不计为修复通过。

证据归约回归覆盖：另一 admitted Attempt 未进入或本地完成未记录、终局前晚成功、非执行使保留失败充分、局部失败仍未决，以及遗漏 admitted blocker 的检测变异。failed 保留原授权与迟到回复，拒绝业务恢复、新授权、settle 和 repeat；未处理回复不记为 consumed。

监视器回归区分 guard/事实与排队报告投递。`lose(r, a)` 只接受 Admitted；在 nonexecution/局部失败后拒绝 lose，不执行 distinct-ID 载荷或持久化其审计。真实延迟报告、验证与审计归属 I2/I3/S4。外部 API 引用固定到实际检查版本，源码段落不是采用测试。

抽样 positivity validator 检查每个请求目标。缺失或零计数必须失败，无关目标正计数不能替代缺项。

## 执行器验证

执行器改变后运行 `mix format --check-formatted`、`mix compile --warnings-as-errors`、`mix test` 和真实 `mix quint.quick`。保留小范围的参数与 witness 正计数回归；命令或超时调用改变时用真实小模型检查配置加载、成功退出和限时退出，不重建假 CLI、日志目录与进程监督设施。

仅注释/空白变化可用语法、格式和语法树等同性代替行为回归：Python 比较去位置属性的 AST 与非注释 token，Elixir 解析后递归去节点位置元数据。若有可执行行或依赖变化，仍执行完整检查。

正例：`admit replacement -> record original logical failure` 保持 NoResult/Executing；替代主体本地成功仍不改变权威知识，记录成功后才出现一个 Ok/Reply。反例：信任动作写入的 valid 字段，或用新 Attempt 的未执行证明清除旧 unknown。

## 本地日志与可读交付

工具原始捕获和反例仅在本地保留，原始 `_apalache-out/` 与历史 evidence 树由 Git 忽略。需要保存终端输出时由调用方重定向。人工报告/README/coverage 说明结果、配置和限制；必需 Markdown 链接指向可提交文档或源码，不依赖本地捕获。

检查保存条件时，直接比较工作树字节与完整索引记录；已有暂存内容保持。`git diff --check` 只检查其对应差异，差异为空不表示文件没有空白问题。日志整理不要求重复未改变模型的抽样/BMC。

Ra 仍为 ADR-007 条件候选，Mnesia/disk_log 是替代比较；实际存储、提供者、ETF、资源和平台支持须满足相应契约的实现验证义务。
