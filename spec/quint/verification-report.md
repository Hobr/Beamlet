# 历史详细套件验证报告

当前主结果见[核心报告](core/verification-report.md)与[核心入口](core/README.md)。本文件是范围缩减前的详细探索历史，不是当前 C1–C6 的验收清单；旧全契约 AC 门禁未因核心验收而通过。以下结果按执行阶段与原依赖哈希限定。

全部原日志、metadata、哈希文件、反例和 compact pack **只在本地保留、Git 忽略**。历史路径 `spec/quint/evidence/` 和 `spec/quint/core/evidence/` 不是新检出依赖。保留用于审计/复现，不纳入版本控制。新检出只能读取本摘要、[覆盖映射](coverage.md)、源码和复现命令，不能独立查看未提交的历史捕获。本轮只改中文文档、链接、忽略与提交范围，没有运行新的检查。

## 来源阶段

| 阶段与模型 SHA256 | 已执行结果 | 对后续源的限制 |
| --- | --- | --- |
| 重试模型 `4822fb0875076ade3793d952d0d3e400eca4d8131d47b854b13623608b10ba9e` | 六 typecheck；53旧场景、13协议、9负控；500条/depth60/seed20261010诊断无采样反例 | 500条不满足10,000要求；后来的模型变化使这些结果成为历史 |
| 独立检查模型 `9eee879ea96cc3d385cf3ff48fb32f237a4b4a73abb2b2f0676a86fc29e4128a` | 七 typecheck、82测试；三组各10,000抽样，无采样反例；修复四类断言并保留三个缺口 probe | 通过的坏行为 probe 不计负控/修复验收；后续保真修复改变依赖 |
| 最终保真检查点 `32e918742ebf7f0e36fc3aaa9ed8e815f1e5aeaf17ee1303e4a93d84cfbc6b67` | 九 typecheck、97测试通过（54场景/13协议/9原变异/8形式维度/1 scheduler/12 review回归变异） | 没有该源的新最终抽样/编译/backend；完整组合界限仍未建立 |

哈希对应各阶段 `architecture.qnt`，不是核心 `model.qnt`。历史原始 runner/依赖身份保留在本地；入口哈希不变也不能证明不同模型依赖相同。保真检查点后只作测试末尾空行整理，不把新字节身份冒充历史运行身份。

<a id="historical-detailed-suite-fidelity-checkpoint"></a>

## 保真修复检查点

观察键回放现在比较原 Attempt、owner、provider/resource、generation/domain、intent 与 payload；恢复授权排除相关 unknown 的旧实例，重连保持实例和进入标记。失败适用声明由求值捕获到 Effect；普通失败不清除旧未知。终态控制与分支来源、选定稳定前缀、完成输入/结果历史、新队列/游标/身份/授权均有独立断言和检测变异。

41转换/26新命令的组合测试改为真实 envelope/receipt；恢复 fixture 匹配四命令前缀；八转换条件 scheduler 经协议调用且最终九回执。本地 evaluate/enter/complete/故障仍独立。新增 StartRun、两种注册不透明 Definition、两层 Scope、精确资源/权限、角色/写入、consistent inspect/export/resource-use 与完成历史。实际代码/模式/ETF/Ra/平台、provider 清理图未实现。

测试容量32容纳该路径；bounded10键保留所有动作及默认 init/step，只限定最多十步新命令探索，不证明请求界限完成。新 Definition 暴露 continue/finish 分类遗漏，已修复 usefulEnabled；无无条件 stutter 或无关权限 fallback。原探测失败仍只在本地保留。

<a id="independent-review-historical-reviewed-source"></a>

## 独立检查的历史发现

没有建立 P0 架构矛盾；以下是模型/属性/覆盖缺陷。旧阶段结论不能在修复后不加时间限定地重用。

| 优先级/发现 | 原证据与处置 | 界限 |
| --- | --- | --- |
| P1 求值捕获 | applyCommit 曾读取提交时配置；Proposal/envelope 改为保留求值意图；evaluationCaptureTest 交错 provider 替换 | 捕获语义修复，不是注册兼容实现验证 |
| P1 故障前态 | 绕 guard 的 suspended applyFail 曾逃过 reference；加入 mode/head/permission/write/business-preservation 检查 | suspendedFailureDetectionTest 检测 |
| P1 结果/回复原子性 | 只写结果遗漏回复的 mutation 曾逃过 reference；检查恰好一条新增 terminal input 与实际前态观测 | missingReplyStallDetectionTest 由 G03/G08/reference 检测 |
| P2 进度分类 | 死 admitted owner / 无 ObserveOp 误判 stall；结果无回复误当 blocked | 显式权限/队列/ID 阻塞；不能用 recorded result 原谅缺少回复 |
| P1 原观察键绑定遗漏 | 同 observation ID 改 binding/intent 的命令曾被接受，独立 reference 失败 | 后来改为 key_conflict 回归；正常随机 step 不生成非法 envelope，抽样不能替代此测试 |
| P1 恢复主体复用 | 旧主体进入/unknown 后被第二 Attempt 复用，旧 G02/reference 接受 | 后来要求新实例；重连不赋予新恢复身份 |
| P1 失败声明遗漏 | 失败是否足以说明整个逻辑操作未捕获 | 后来显式 capture，局部失败未决；声明真实性仍前提 |
| P1 控制/派生断言不足 | guard 绕过后的 terminal resume 与 fabricated boundary 曾未被检测 | 后来独立检查前态生命周期/稳定边界来源及 fresh权限 |
| P1 完整组合界限未完成 | serializer 膨胀/超时，depth1也未完成 | 没有较小界限；focused 不能替代完整组合 |
| P2 envelope集成与形式范围遗漏 | 旧41转换路径直接 helper；Definition/Scope/资源/角色/access/历史未完整展开 | 后来增加上述有界维度，实际运行时仍未执行 |

原三个 gap probe（绑定冲突、恢复旧主体、终态控制）故意演示坏行为，是未完成验收证据，不是成功负控。原修复四类断言后82测试含53旧场景、13协议、9原负控、4修复回归、3gap probe。手工 key/cursor 损坏只能证明相应事实敏感性，不自动建立可达动作 mutation 覆盖。

| 独立检查抽样 | init / step / depth / seed | 实际结果 |
| --- | --- | --- |
| 默认完整组合 | init / step /60/20261007，10,000条 | 无采样反例，381.316秒求值/388秒墙钟；恢复消费0，分支新工作121 |
| 可达恢复 fixture | recoveryInit / step /60/20261008，10,000条 | 无采样反例，385.976秒/393秒；恢复消费17，分支工作50 |
| 条件调度 | progressInit / progressStep /40/20261009，10,000条 | 无采样反例，43.899秒/51秒；恢复消费10,000，同一确定路径 |

三个运行预算420/420/120秒；depth60覆盖41转换路径的深度，但不等于 envelope 确定集成已完成。默认恢复0仍是 coverage gap，fixture只能证明在其起点可达，条件重复不是公平性。实际 source 依赖在运行期间未变，后来的 test-only probe 单独哈希；进一步保真修复后这些抽样不再验证新源。

<a id="retry-checkpoint-evidence-superseded-source"></a>

## 重试诊断

默认 init/step/Rust 诊断500条/depth60/seed20261010，17.525秒，exit0，无采样反例；恢复0、分支新工作2、retry464、admit5、observe4。日志复现 seed0x1416a9f，命令 seed仍20261010。500条不满足原10,000要求。

完整组合 depth1/90秒/port8831、main architectureBounded/invariant architectureSafety，在 Quint `json-bigint` 序列化发生 `RangeError: Invalid string length`，exit1，backend未启动，没有符号状态/完成界限，未重试 depth10。共享多实例结构元数据膨胀后来支持核心拆分单实例入口，而不是删除语义或自定义 compiler。

历史 history 测试诊断只是预期计数错：前态4、新审计回执5/execution revision3、repeat 后6，原键重放仍6；仅改测试预期，不改协议归一化。precheck 后来仅写本地 actual，durable observation 单独命令；不把本地状态变化当权威记录。

<a id="historical-execution-evidence-superseded-hashes"></a>

## 更早执行记录

使用现有 Nix Quint0.32.0、Rust 模拟、正式 TypeScript 测试、Apalache0.56.1/build70cdaf4 / OpenJDK21。没有依赖安装或 flake 改动。

| 检查 | 历史配置与实际结果 | 限制 |
| --- | --- | --- |
| typecheck/场景 | 五维护文件通过；architecture_test/TypeScript/`.*Test`/seed20261007，53场景 | 旧源身份 |
| 独立负控 | 同 seed四项：主体继承、重复终局回复、旧提案、repeat复用被检测 | 仅这些 mutations |
| 完整组合抽样 | architectureAnalysis/default init+step；10,000/depth100/seed20261007；exit0，无采样反例，437.076秒 | 非穷举；恢复消费0 |
| 恢复 fixture组合 | architectureRecoveryAnalysis/recoveryInit+step；10,000/depth100/seed20261008；exit0，无采样反例，462.522秒；恢复33/分支291 | 只改变起点，不替代默认 gate |
| 条件调度 | architectureProgressAnalysis/progressInit+progressStep；10,000/depth40/seed20261009；exit0，无采样反例，27.800秒；恢复10,000 | 相同八转换路径，不证明一般活性 |
| 代表确定路径 | combinedInterleavingTest/TypeScript/seed20261007；41转换，恢复消费/控制器关卡/源分支工作到达 | 历史 helper路径，不等同后来 envelope路径 |

扩展域2Run/每Run2Effect/每Effect3Attempt/3owner/FIFO12，Run1初始不存在；缩小组合保留2Run/1Effect/2Attempt/3owner/FIFO4与全部动作/故障。revision不回绕。早期默认抽样：inputs9433、commits4272、admit336、enter238、unknown44、observe167、repeat6、settle12、terminal consumption12、branches8531、branch work417；复合恢复消费为0。确定 recoveryPermissionTest/41路径与fixture33建立可达性，不能抹去默认稀疏缺口；执行器 witness gate 仍非零。

<a id="historical-bounded-backend-attempts"></a>

## 历史后端尝试

所有行使用正式 `quint verify --backend apalache`，random-transitions=false；**均没有完成组合界限**。verbosity1 只在结束输出结论，空 CLI 日志不能推断未运行或成功；原 backend capture 只在本地保留。

| 尝试 | 配置/预算 | 实际未完成范围 |
| --- | --- | --- |
| 扩展开发组合 | architectureSafety/default init+step/depth10/180秒 | exit124，State1分支/属性仍在检查 |
| 缩小开发组合 | 2Run/1Effect/2Attempt/FIFO4/architectureSafety/depth10/600秒 | exit124，State3/transition20仍在检查；无 depth3 完成结果 |
| 等价 invariant 编码调查 | 最终缩小域/modelCheckSafety/depth10/480秒 | exit124，前次backend占资源，不能当 fresh完整检查 |
| 最终 fresh组合 | architectureBounded/modelCheckSafety/default/depth10/180秒/port8825 | exit124，完成 parsing/typecheck/inline，State0 invariant 开始；请求界限未完成 |
| 最终条件 focused | architectureProgressAnalysis/progressInit/progressStep/conditionalSafety/depth20/180秒/port8824 | exit124，Snowcat/desugar后 InlinePass仍在执行 |
| 后来独立 depth1 诊断 | default完整架构域/depth1/45秒/port8833 | exit124，无 fresh backend日志；无任何较小界限 |

```sh
timeout 180 quint verify spec/quint/architecture.qnt --main architectureBounded \
  --invariant modelCheckSafety --max-steps 10 --backend apalache \
  --server-endpoint localhost:8825 --verbosity 1
timeout 180 quint verify spec/quint/architecture.qnt --main architectureProgressAnalysis \
  --init progressInit --step progressStep --invariant conditionalSafety \
  --max-steps 20 --backend apalache --server-endpoint localhost:8824 --verbosity 1
```

这是历史命令记录，不是本轮执行建议或新结果。早期缩减共享审计只保留独立断言读取的事实、减少参与者/队列；整数 truth indicator 后来删除，Boolean-set 编码实验因编译代价放弃。没有通过删组件/故障/保证获得 solver pass。开发尝试早于最终属性/控制变化，只反映资源限制，不能验证新源。

<a id="historical-global-conclusions-see-current-checkpoint-above"></a>

## 全局结论与前提

G01–G06 在历史测试/抽样中分别检查提交事实、绑定授权/单次进入、未知与唯一结果、输入顺序/业务原子性、终态/暂停、稳定前缀与 fresh分支。G07只是模型图无 Agent 分支，不检查不存在的产品 imports/API；G08为有限域有用动作分类，不是一般 liveness。reference检查具体转换的保留、进入、FIFO与派生变化，不是无界 refinement证明。

线性化持久权威、真实主体身份、提供者分类/去重、合法输入/模式/归档值与可信成员是前提。实际 Ra/quorum/磁盘、监督进程、schema/authentication、ETF、安全/预算、资源清理、平台/设备和两种生产应用均未验证。

<a id="defect-classification-and-regressions"></a>

## 早期缺陷分类

G06 曾把 absent Run 的 placeholder 当已保留边界；fork正常替换时，保留比较应只检查前态存在 Run，来源保证未改。G03 曾禁止终局 Error 与任何后续 unknown 共存；seed20261008在280条后发现旧 unknown/repeat/新admit/旧失败选择/新Attempt晚unknown，复现 seed0x13dcdda。原阶段改为检查选择时知识，并保留 Lost 证据与真实非执行零调用事实。该早期解释后来又受核心 admitted-work 修复约束，不能当成当前“admitted不阻止失败”的验收；见[当前核心结果](core/verification-report.md)。

长 then/expect 在 Rust evaluator 出现 `QNT516` recursion limit，测试转正式 TypeScript，模拟保持 Rust。旧失败与中断日志只用于诊断，不替代最终结果。未建立需要改变架构保证的矛盾。

<a id="acceptance-gaps-and-next-work"></a>

## 历史验收缺口与当前边界

原库存含18需求、17场景、88矩阵行。保真修复使部分 bounded协议维度补齐，不意味着原全任务验收通过。原 AC5最终新源10,000抽样、AC3默认 witness gate、AC6完整组合depth10、AC10一般/temporal进度仍未全部完成；query/resource/Definition等旧遗漏虽在后来模型补齐，实际运行时仍缺。用户之后明确改为核心 C1–C6 范围，这些旧 gate 被取代而非通过。

当前核心46测试、10,000depth60抽样/十项正 witness、24转换路径有来源绑定证据；完整组合depth10仍240.054秒/State5/exit124无结论，恢复depth14只覆盖指定调度。任务保持 in_progress，提交/归档另行处理。Mnesia / disk_log 仅为既有 ADR007替代比较；没有新增依赖、后端或运行时，Ra仍是条件候选。
