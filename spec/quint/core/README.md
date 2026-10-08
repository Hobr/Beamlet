# 核心架构验证

这里是当前验证范围的主入口。核心抽象用于检查 Beamlet [架构契约](../../architecture/index.md)的 C1–C6 问题；它不是大型探索模型的等价优化，也不代表完整运行时实现。

[model.qnt](model.qnt)保留权威、主体绑定执行、计算与控制、稳定历史前缀四个边界。[composition.qnt](composition.qnt)只实例化一次：两个 Run，每个 Run 一个逻辑 Effect，每个 Effect 两个 Attempt，两个主体实例，每个 Run 的 FIFO 容量为6。初始化时只有 Run0；Run1 从选定稳定边界创建。[small.qnt](small.qnt)使用同一 step，限制为一个 Run / FIFO4，仅用于诊断。

```sh
mix quint.quick     # 六项类型检查、确定性竞态/变异及恢复路径
mix quint.simulate  # quick 加10,000条组合抽样
mix quint.verify    # quick 加实际 depth10 后端尝试
mix quint           # 默认执行全部检查
mix quint --cores 16 --timeout 0  # 完整核心套件，无后端时间截止
```

使用 Quint0.32.0 / 随附 Apalache0.56.1 / Java21。Mix 使用[薄命令入口](../check.exs)，也可运行 `elixir spec/quint/check.exs quick`。核心与补充共用以下参数，`mix quint --help` 查看帮助：

| 参数 | 适用范围 | 约束与默认值 |
| --- | --- | --- |
| `--suite core\|supplemental` | 全部模式 | 默认 `core` |
| `--cores N` | 有界后端 | 正整数，Z3 SMT 线程数，默认8 |
| `--timeout N` | 有界后端 | 非负整数秒，每次检查单独计时，默认0（不限时） |
| `--max-samples N` | 确定性测试、模拟 | 正整数；模拟默认10,000，固定 seed 的测试默认1 |
| `--max-steps N` | 模拟、有界后端 | 非负整数；核心模拟默认60，后端默认10 |
| `--seed N` | 确定性测试、模拟 | 非负整数；核心默认20261014，补充保留各场景原 seed |
| `--verbosity N` | 测试、模拟、有界后端 | 0–5；模拟要求至少1以校验 witness；模拟默认1，测试和后端默认2 |
| `--n-threads N` | Rust 模拟 | 正整数，默认使用 Quint 的16线程 |
| `--match REGEX` | 确定性测试 | 覆盖测试名筛选；默认保持各测试文件原筛选 |
| `--server-endpoint HOST:PORT` | 有界后端 | Apalache 服务地址，默认 `localhost:8822`；端口1–65535 |

```sh
mix quint.simulate --max-samples 20000 --max-steps 80 --seed 42 --n-threads 4
mix quint.verify --max-steps 6 --cores 4 --timeout 900 --verbosity 1 --server-endpoint localhost:8823
mix quint.quick --match '.*Test' --seed 42 --max-samples 2
```

未指定的参数保留原默认值。参数仅传给支持它的 Quint 子命令：例如 `verify` 前置 quick 的测试会接收 `--seed` / `--match`，但不接收 `--max-steps`。`all` 的 `--max-steps` 同时覆盖模拟和后端深度，`--max-samples` 同时覆盖测试和模拟。补充模拟默认深度为100/100/40，后端为10/8；覆盖值应用到每个相关场景。Z3 `--cores` 与 Rust `--n-threads` 分别控制两个后端的并发，线程数不绑定具体 CPU 核心，也不保证固定倍数加速。并行后端检查可使用不同的 `--server-endpoint localhost:PORT`；Quint 自动启动本地服务。Quint0.32 的地址解析仅支持字母、数字和点组成的主机名或 IPv4。减少抽样或深度可能使 witness 缺失，入口仍返回非零；筛选测试通过只代表选中的测试。

类型检查、测试和后端进度直接显示在终端，首个失败即停止。抽样结束显示原始输出并检查每个请求 witness 是否有正计数。限时后端调用使用系统 GNU `timeout`，超时仍是无结论。入口只临时生成线程配置并在调用结束后删除；不维护日志目录、逐项退出码/耗时文件或检查点汇总。Apalache 自己生成的 `_apalache-out/` 是工具原始产物，已由 Git 忽略。

运行日志仅保存在本地，Git 不包含原始捕获。新检出从[验证报告](verification-report.md)读取结果、配置与限制，并通过上述命令生成自己的日志。

[协议设计评审](../../architecture/protocol-review-2026-10-08.md#disposition)接受了 ADR-008 技术设计；ADR-007 中 Ra 仍是条件候选，采用验证未执行。

<a id="questions-and-correspondence"></a>

## 验证问题与来源对应

| 问题 | 保留的区别 | 来源与独立断言 |
| --- | --- | --- |
| C1：提交事实是否跨控制变更保留？ | 不可变意图、捕获声明、原授权、单调进入标记与结果；接管仅改变控制纪元 | [权威契约](../../architecture/authority-and-recovery.md#3-契约)；`C1` / `identityRetention` |
| C2：调用是否必须有绑定原主体的一次授权？ | admit 与 enter 分开；每个 Attempt 保留原主体与单调调用计数；重复分发不重入 | 权威主体契约 / S4；`C2` |
| C3：未知、恢复与唯一结果是否一致？ | 权威知识与本地完成分开；捕获失败含义；repeat 在授权时消费；结果与一条回复同时提交 | [结果与裁定](../../architecture/authority-and-recovery.md#invocation-resolution)；S11；`C3` / `terminalChoice` |
| C4：应用是否按权威输入顺序原子推进？ | 持有 epoch/revision/head 提案；状态、输入处置与新 Effect 同时提交；过时通知只在队首处置 | [计算与输入调度](../../architecture/computation-and-effects.md#3-契约)；S2/S14；`C4` / `applicationRetention` |
| C5：暂停与终态是否封闭新工作但保留旧授权？ | active/suspended 与 open/terminal 分开；暂停阻止新 admit/commit，旧授权仍可进入与报告 | [生命周期](../../architecture/lifecycle-and-archives.md#3-契约)；S19；`C5` |
| C6：分支是否只复制选定稳定前缀？ | 稳定资格在提交时记录；前缀不可变；新分支 suspended、空授权、新队列和新身份 | 生命周期稳定边界 / S13/S17；`C6` / `boundaryRetention` |

业务状态用不透明整数表示已提交转换。Definition 的候选返回为 invoke、wait、continue、finish 或 fault。ready 前缀在新分支重建一条 Continuation；finished 前缀保持终态。`Control.origin` 保存所选前缀的状态、修订、推进状态、生命周期和历史结果。新 Effect 使用分支自己的 token，不继承历史结果对应的活动授权。

求值、commit、admit、enter、本地 complete、权威 record 与 consume 都是独立转换。共同 `step` 还包括暂停/恢复、接管、repeat/settle、预检拒绝、重复分发、断连/死亡/重连、权威可用性、外部输入与分支。死亡实例不复活；重连保留实例身份和进入标记。较早 unknown Attempt 可能在新 Attempt 已授权后继续完成。

断言读取真实的前态控制、Effect、Attempt、提案、输入与边界事实，不信任动作写入的“有效”标记，也不复制一套完整参考状态机。边界资格从提交后的因果事实独立检查。小型 Prior 只保留事件相关 Run/Attempt 和来源前缀，并检查观测与已处置输入保留、队首消费、Invoke 意图创建及 repeat 授权消费的原子性。

`Attempt.evidence` 是有效观测分类，区别于物理 `actual` 和 `knowledge` 标签。`unresolved` 根据已提交授权、观测与捕获的失败含义判断，不能从 `Recorded` 推断逻辑已解决。另一 admitted Attempt 即使已在本地完成但尚未记录，仍阻止终局失败。完整载荷、键、原始来源和审计历史由 I1/I2 接口保证，不重复展开为模型状态。

正常 `reduce` 同时读取两个 Attempt 的保留观测；独立属性直接检查前态授权与观测，不调用 `reduce`、`observed`、`unresolved` 或记录 guard 作为证明。局部失败在 `Recorded` 后仍可未决。新 `NotExecuted` 不解除另一 Attempt 的 unknown/局部失败；较早 unknown 自身被有效证明未执行后，另一已保留的逻辑失败才能归约为唯一 Error。旧模型的失败回归与坏行为诊断只作为历史缺口保留，不能计入修复通过。

<a id="named-interface-assumptions"></a>

## 显式接口前提

- **I1：持久权威。** 命令原子、线性化且持久保留；可用性只控制接口访问。模型不验证 Ra、复制、磁盘或 quorum。
- **I2：有效命令。** 授权、载荷、稳定 command/observation/input 键、执行修订与回执优先幂等由接口提供。不同事件表示独立合法逻辑命令；完整错误优先级和 DTO 不在核心内。
- **I3：兼容执行。** 注册实现、绑定/资源兼容和真实原主体观测成立。token 与实例身份显式保留；提供者图、代次变化、清理和资源查找未展开。`conclusive` 投影[捕获失败声明](../../architecture/capability-composition.md#failure-declaration)：`false` 为默认 Attempt 局部失败，`true` 为兼容的逻辑失败契约。版本、注册表与提供者符合性仍须实现验证；逻辑失败也不能越过其他未决授权。
- **I4：有效前缀。** Definition、状态与结果是可移植兼容值；模型检查资格和权限隔离，不验证归档解码、ETF、代码安装或平台信任。

这些都是前提。admit/resolve 直接在权威边界执行；延迟命令载荷和具体 revision 错误归属 I2。持有的业务提案保留 epoch/revision/head，因此旧控制竞态仍显式检查。核心不覆盖完整 R/S/P 表；旧[覆盖审计](../coverage.md)只提供补充来源映射。

<a id="conditional-recovery-obligation"></a>

## 条件恢复范围

[recovery.qnt](recovery.qnt)仅导入 Run0/FIFO4，使用默认初始化和受限14转换 `step`：捕获/提交、原授权/进入、失联/unknown、显式 repeat、新主体授权/进入/成功/记录、过时通知处置，以及消费 Reply 的合法 finish。[recovery_test.qnt](recovery_test.qnt)逐步检查 safety、前提与严格递减的非负 rank，最终 consumed/finished；rank 监视器不增加核心状态，`recovered` 初始为 false，也没有终态 stutter。

前提包括权威可写、控制 active、无新增故障/控制/输入干扰、活着且兼容并成功的替代主体、提供 repeat 许可、合法 finish、容量及每个指定动作最终得到调度。测试建立该具体路径；完成的 depth14 只检查这个调度。开放 `composition.step` 保留全部故障/控制动作，不能由恢复 witness 或 focused bound 推出一般活性或完整组合安全。未来责任见[权威恢复表](../../architecture/authority-and-recovery.md#evidence-reduction)与[I1–I4义务](../../architecture/boundaries.md#interface-obligations)。

<a id="waiting-finite-bounds-and-evidence-strength"></a>

## 等待、有限域与证据强度

ID 不复用，计数不回绕。FIFO 满、Attempt 用尽、目标 Run 已存在或活主体容量耗尽，是有限抽象限制。暂停、权威不可用、空收件箱或 unknown 等待 repeat/settle，是契约或环境等待。存在合法工作、足够新身份与恢复接口却无对应动作，才是模型停滞；不安装循环 blocked 分类或无条件 stutter 来掩盖它。

`step` 总能切换真实的权威可用性；环境状态变化不证明业务进度。重复分发是唯一不改变业务事实的具名事件，要求原 Attempt 已进入，且 `C2` 检查原主体。故障与控制可以持续阻塞；恢复消费可达不代表必然发生。

当前[报告](verification-report.md)记录46测试、24转换代表路径、10,000 depth60/seed20261014抽样及十个正 witness。消费5/恢复消费1仍稀疏。组合 depth10/240秒在 State5 超时，不能推出任何较小界限；受限恢复 depth14 NoError 只适用于明确调度。新增三个 monitor 测试只检查 guard/事实，不执行不同键的排队报告或审计持久化；实际行为仍归属 I2/I3。

大型探索套件是[补充模型](../README.md)，其序列化失败、未完成界限与覆盖缺口另有范围限定。技术设计接受不等于完整形式或运行时验证。
