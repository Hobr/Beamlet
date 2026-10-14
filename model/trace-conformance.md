# Quint 轨迹与真实持久实现重放

在仓库根目录运行统一入口：

```sh
mix run scripts/check_trace_conformance.exs --suite all --seed 42
```

入口先执行新的 Worker、Caller/Continuation 轨迹，再执行已有 Domain、reconciliation 与资源 fencing 对照。
任一类型检查、模型动作、SQL/Runtime 操作或投影比较失败，命令以非零状态退出。
可以用 `--suite worker`、`--suite caller`、`--suite traces` 或 `--suite oracles` 分别运行。
新轨迹使用 Quint Rust backend，单线程；需要本机 `quint` 和当前 umbrella 依赖。

## 覆盖预算

| 检查组 | 固定预算 | 覆盖窗口 |
| --- | --- | --- |
| Worker 新轨迹 | 4 条历史，54 个检查点 | 授权/派发/真实调用、重复 grant、Authority 服务停止和恢复、原报告保留至 Stored、Worker 结果丢失后查询、新 incarnation 拒绝旧 grant；分别叠加取消与迟到 Success |
| Caller/Continuation 新轨迹 | 3 条历史，57 个检查点 | A/B 共享 Worker 和相同本地 Execution ID；A 成功且 B 未完成时决定 C；在 decision 提交后、manifest 注册后、后继提交丢回复后分别停止并重建 Caller 库服务；C 完成后再完成 B |
| Domain 既有 oracle | 2,000 组报告 + 1,568 组严格重试 + 1,568 组接受重复风险的重试 | 首份 Knowledge、冲突、报告去重、原契约窗口、调用前资格与显式风险接受 |
| Reconciliation 既有 oracle | 2,048 组命令 + 144 组撤销 | 当前判断、原命令重放、权限、修订、冲突覆盖、处置归属和撤销 |
| 资源既有 oracle | 2 条历史，30 个检查点 | 独立 Authority/资源 SQL，fencing、丢排除回复、双库重启、替代、资源提交、取消和迟到报告 |

新轨迹是**定向、有限的动作序列**：`traceInit` 内部通过 `then` 执行既有模型动作，
`--max-samples 1 --max-steps 0` 只是不在定向前缀之外继续采样，并不代表没有执行动作。
variant 固定故障窗口，seed 记录在产物中；改变 seed 不增加这些固定前缀的逻辑覆盖。
这里没有声称覆盖任意长度轨迹、所有动作排列或全部 Quint 模块。

## 预期与实际如何分离

[`worker.qnt`](../scripts/conformance/worker.qnt) 导入原 `beamletCore`；
[`caller.qnt`](../scripts/conformance/caller.qnt) 导入原 `continuationProfiles`。
包装层仅添加 checkpoint 列表、投影和 frame，协议状态转换调用既有动作；每个检查点要求原有
`safety` / `continuationSafety`。没有修改 `model/quint` 下的规则，也没有在 Elixir 中重写一套预期转换。
组合动作将新增的 checkpoint 变量逐个传递到每个 primitive frame，避免中间动作遗漏状态赋值。

[`Trace`](../apps/beamlet_specs/lib/beamlet/specs/trace.ex) 先复制当前模型并类型检查，然后由 Quint 生成 ITF。
Elixir 驱动器只读取操作标签，操作真实 Coordinator、Worker、Caller 和 SQL 资源，重新读取持久事实形成实际投影。
预期行的其余字段不会成为驱动器的状态输入。比较要求整个投影严格相等；缺字段、多字段和不相等的值都失败。
ITF 支持普通及带模块前缀的 `rows` 变量、嵌套列表和精确整数，缺少或存在多个 checkpoint 变量会失败。

新的 Worker 轨迹比较 Intent/Execution 生命周期、当前 Execution、首次 Knowledge、judgment revision、
报告数和来源类型、冲突资格、Outcome 和值，以及真实资源调用次数/完成状态、Worker 存活和 incarnation。
Caller 轨迹同时比较三个 Intent 的生命周期、Knowledge、报告/回调、Outcome/值及资源状态，
完整 catalog 数、两个 round 的完成状态、后继输入和 decision 消费值。
还独立核对 decision 的 owner/collection/step/rule、原 Intent、完整原 Outcome、后继身份/定义和 manifest 对应关系。

Runtime facade 可能合并多个模型动作：例如 `Worker.run` 合并领取、授权与派发，
`Caller.advance` 合并提交、关联、读取和收集。检查点位于对应可观测边界，
并非这些 facade 内每条 SQL 语句或模型内部每个 message frame 都有一次实际状态比较。
UUID、文本身份和正文是既有有界整数的工程表示；投影按明确的原提交身份关联，不按 catalog 返回顺序猜测 Intent。
Quint 的 Agent read cache 是易失的，而实现可持久保存更多已收集 Outcome；新轨迹比较提交的 round/decision，
不把 Caller 的持久缓存伪装成重启后清空的 `agentLocals`。

## 故障与证据

驱动器使用三个独立文件边界：Authority、资源和 Caller。资源 fixture 在真实 SQL 中记录调用，
**不设置调用去重约束**，因此重复调用会增加计数并造成差异，不能由 fixture 隐藏。
资源完成、Handler 返回和 Authority 入账分别推进；callback 必须与独立资源 SQL 中的完成事实一致。
fixture 是受信本地测试能力，不是第三方 Provider 或远端认证实现。

Authority/Caller 服务停止时，独立 observer 连接只读取同一持久文件供验收；它不代替已停止服务执行命令。
实际命令仍经过原 Repo/Coordinator/Caller。该故障表示服务/进程不可用，
不表示数据库磁盘离线、所有连接同时消失、SIGKILL、断电或文件系统损坏。
Worker 崩溃后，已经调用的资源仍可独立完成；取消不停止外部效果，也不改变既有唯一 Outcome。
等待使用消息和进程监视器，有界超时直接失败，不用 sleep 来猜测异步结果已就绪。

每次运行输出独立产物目录，保留：

- 当前模型副本、包装源码、Quint 版本及源码 SHA-256 manifest。
- 每条历史的 seed、variant、backend、线程/采样预算和原始 ITF/Quint 日志。
- 完整预期 JSON、逐检查点实际 JSONL，以及三个真实 SQLite 文件。
- 首个差异的 index、操作标签、预期与实际；操作异常另外记录，后续动作不再执行。

`apps/beamlet_specs/test/trace_test.exs` 检查整数/命名空间解码、空/歧义轨迹拒绝、顺序重放、
故意不匹配、多/缺字段和驱动器异常。故意将调用数从 1 改成 2 会在首个检查点失败并保存证据。

## 本轮验证记录

统一入口 `--suite all --seed 42` 完整通过，包含上表所有对照组。
新增 Worker/Caller 轨迹另以 seed=1 全部复跑通过；固定前缀的检查点数量仍为 54/57，不据此翻倍覆盖数。
完整 umbrella 316 项测试/doctest、强制编译 warnings-as-errors、变更文件格式/diff、
新增/变更 Elixir 文件的主动 LSP 检查及新增代码范围的严格 Credo 检查通过。
扩大到整个 `beamlet_specs` 的 Credo 扫描仍报告未修改文件中既有的 alias/复杂度提示，未将其记作通过。
这些检查不替代下面列出的后续对应工作。

## 仍未覆盖的对应工作

统一入口不等于统一的全动作 refinement 引擎。Reconciliation 目前接入的是已有纯 oracle 矩阵，
资源 fencing 接入的是已有选定 SQL 历史；它们尚未与新 Worker/Caller 轨迹自动交错。
时钟前跳/回拨、过期屏障、幂等窗口变化、治理退役/取代/撤销、资源切换、并发 Coordinator/命令和任意消息乱序，
仍需在同一轨迹驱动器中扩展。这些行为已有各自的模型或验收测试，不能合并计数为新的全轨迹覆盖。
PostgreSQL、真实 power-loss、备份/克隆隔离、远端 Transport、第三方资源契约和任意 Agent workflow 也不由本次结果证明。
