# 详细模型验证报告

[核心 C1–C6](core/README.md)是主验证范围。本报告说明详细探索模型的技术结果与缺口，配合[覆盖映射](coverage.md)查找对应测试。详细模型展开了命令/回执、绑定、Scope、角色和资源等有界维度，核心结果不能补全它的组合界限。

## 模型与最近的确定性检查

[architecture.qnt](architecture.qnt)在同一状态上交错权威、求值/提交、控制、主体进入、观测、FIFO 与分支；[reference.qnt](reference.qnt)独立检查可观察前态及转换。[types.qnt](types.qnt)定义封闭记录和变体。扩展域为2 Run、每 Run 2 Effect、每 Effect 3 Attempt、3主体实例、每 Run FIFO12；bounded 域为2 Run、每 Run 1 Effect、每 Effect 2 Attempt、3主体、FIFO4。

详细模型最近完成九项 typecheck 和97项确定性测试：54场景、13协议、9原检测变异、8形式维度、1条件调度、12回归/变异。41转换/26新命令的组合路径使用真实 envelope/receipt；恢复 fixture 匹配四命令前缀，八转换条件 scheduler 最终保留九条命令。测试命令键容量32，bounded 容量10；这不表示41转换路径适合 bounded 域或界限已完成。

后续保真修复没有新的最终10,000条抽样、模型编译或后端结果。下面的早期抽样属于修复前版本，不能验证后来变化的模型依赖。已有原始日志只在本地保留，新检出读取结果摘要与源码，并通过[当前命令](README.md)生成自己的日志。

## 实质缺陷与修复

| 缺陷 | 修复与可执行检查 | 仍需验证 |
| --- | --- | --- |
| 提交时读取当前配置，改变求值语义 | Proposal/envelope 保留求值时捕获；evaluationCaptureTest 交错提供者替换 | 真实注册版本与兼容提供者 |
| 失败转换漏查前态控制 | reference 检查 mode/head/permission/write 与业务状态保留；suspendedFailureDetectionTest 检测 guard 绕过 | 宿主与权威实际故障竞态 |
| 终局结果遗漏原子回复 | G03/G08/reference 要求恰好一条新增终局输入与有效前态观测；missingReplyStallDetectionTest | 持久事务与收件箱修复 |
| 进度分类遗漏 continue/finish，或误把缺回复当阻塞 | usefulEnabled 覆盖实际合法返回，区分权限、队列、身份耗尽与缺少回复 | 分类不是一般活性证明 |
| observation_id 重放漏原绑定与意图 | 比较 Attempt/owner/provider/resource/generation/domain/intent/payload，冲突要求 key_conflict | 真实观测模式与来源真实性 |
| 恢复复用 unknown 的旧主体 | 新 Attempt 排除相关旧实例；重连保留实例与进入标记 | 实例身份分配与真实进程重启 |
| 失败适用声明缺失 | 从 evaluation 捕获到 Effect；局部失败不能清除旧未知，检测伪造终局结果 | 具体操作的失败分类符合性 |
| 终态控制、分支来源断言不足 | 独立检查前态 lifetime、稳定边界与新身份/游标/队列/授权；检测 terminal resume 和 fabricated boundary | 真实归档前缀、兼容性与激活 |

StartRun/初始 ready、两种不透明注册 Definition、两层 Scope、资源身份/权限、角色/写入资格、一致检查/导出/资源使用及完成历史已有有界模型与 formal_test 回归；实际产品 API、认证、提供者清理图、ETF、Ra 与平台仍未执行。

早期 G06 曾把不存在 Run 的占位边界当保留边界，修复为只检查前态存在的 Run。早期 G03 曾错误拒绝终局后保留 unknown；终局结果保持与证据保留应分开。这一修复不允许在其他 admitted 工作仍未决时提前选择失败，当前规则以[核心证据归约](core/verification-report.md)为准。

故意展示绑定冲突、旧主体恢复和终态控制坏行为的三个 gap probe 曾包含在82项早期测试中；它们不计成功检测变异。后来已转为要求拒绝/检测的回归。手工损坏 key/cursor 只证明事实敏感性，不能自动建立可达动作变异覆盖。

## 修复前的抽样结果

工具为 Quint0.32.0、Rust 模拟、正式 TypeScript 测试、Apalache0.56.1（build70cdaf4）与 Java21。长 then/expect 链曾触发 Rust JSON recursion limit（QNT516），确定测试使用 TypeScript。

| 配置 | init / step、数量、深度、seed | 实际结果与限制 |
| --- | --- | --- |
| 早期默认组合 | architectureAnalysis，init/step，10,000条/depth100/20261007 | exit0，无采样反例，437.076秒；恢复消费0 |
| 早期可达 unknown fixture | architectureRecoveryAnalysis，recoveryInit/step，10,000条/depth100/20261008 | exit0，无采样反例，462.522秒；恢复消费33、分支工作291；只改变起点 |
| 早期条件调度 | architectureProgressAnalysis，progressInit/progressStep，10,000条/depth40/20261009 | exit0，无采样反例，27.800秒；恢复消费10,000，重复同一八转换路径 |
| 命令重试诊断 | 默认 init/step，500条/depth60/20261010 | exit0，无采样反例，17.525秒；恢复0、分支2、retry464、admit5、observe4；仅诊断 |
| 断言修复后默认组合 | init/step，10,000条/depth60/20261007 | exit0，无采样反例，381.316秒求值/388秒墙钟；恢复0、分支121 |
| 断言修复后可达 fixture | recoveryInit/step，10,000条/depth60/20261008 | exit0，无采样反例，385.976秒/393秒；恢复17、分支50 |
| 断言修复后条件调度 | progressInit/progressStep，10,000条/depth40/20261009 | exit0，无采样反例，43.899秒/51秒；恢复10,000 |

默认恢复目标为0是抽样覆盖缺口。fixture 的正计数只能证明该起点下可达，同一路径反复完成不证明公平性或一般活性。早期确定路径使用 helper，不能等同于后来 envelope 集成路径。执行器对所有请求 witness 缺失或零值返回非零，即使抽样命令本身 exit0。

## 后端结果与工具限制

以下正式 Apalache 尝试均未完成组合界限，random-transitions=false。正在检查 StateK 只表示进度，不是 depthK 完成证明。

| 尝试 | 配置与预算 | 实际结果 |
| --- | --- | --- |
| 扩展组合 | architectureSafety / init+step / depth10 / 180秒 | exit124，State1仍在检查 |
| 缩小组合 | 2 Run/1 Effect/2 Attempt/FIFO4 / depth10 / 600秒 | exit124，State3仍在检查 |
| 缩小组合最终尝试 | architectureBounded / modelCheckSafety / init+step / depth10 / 180秒 | exit124，解析、类型与内联完成后仍在检查 State0 |
| 条件恢复尝试 | architectureProgressAnalysis / progressInit+progressStep / conditionalSafety / depth20 / 180秒 | exit124，仍在 InlinePass |
| depth1诊断 | architectureBounded / architectureSafety / 90秒 | exit1，json-bigint 序列化 RangeError: Invalid string length，后端未启动 |
| 后续 depth1诊断 | 默认组合 / 45秒 | exit124，没有可归属的新 backend 日志 |

同一解析文件内多个具体实例的结构元数据膨胀导致序列化问题，核心因此使用分离的单实例入口。不能通过删除组件、故障或保证来取得后端通过。早期共享后端占用资源的480秒编码调查不构成独立完成检查。

## 命令与证据强度

```sh
mix quint.supplemental quick
mix quint.supplemental simulate
QUINT_VERIFY_TIMEOUT=180 mix quint.supplemental verify
quint test spec/quint/architecture_test.qnt --main architecture_test --match combinedInterleavingTest --backend typescript --seed 20261007 --out-itf '/tmp/combined_{test}_{seq}.itf.json'
```

`verify` 请求当前补充组合 depth10 与条件调度 depth8，配置见[说明](README.md)；这与上表历史 depth20 尝试不同。执行命令会生成新结果，当前报告不宣称重新执行了早期抽样或后端检查。

G01–G06 分别检查提交事实、绑定授权/单次进入、未知与唯一结果、FIFO/原子推进、控制生命周期和稳定分支。G07 仅检查模型无 Agent 专用分支，G08 是有限域动作分类；reference 不是无界精化证明。

线性化持久权威、可信实例身份、真实提供者分类/去重、合法数据与可信成员是前提。详细模型尚无完成的组合 depth10，也无修复后最终抽样结果；真实 Ra/quorum/磁盘、监督进程、认证/schema、ETF/预算、资源清理和平台支持均待实现验证。主[核心报告](core/verification-report.md)提供较小抽象的结果与同样明确的限制。
