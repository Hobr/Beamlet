# ADR-008 协议补充与条件实现评审记录

证据只保留在本地，整个 `spec/quint/evidence/` 与 `spec/quint/core/evidence/`（包括 compact pack）都受 Git 忽略，不纳入提交。新检出从[核心报告](../quint/core/verification-report.md)读取来源绑定的结果、配置、限制与复现命令，不能独立查看未提交的原日志。本次文件整理与中文文档更新没有新增执行结果，也不改变技术验收。

<a id="disposition"></a>

日期：2026-10-08。归属：任务 `10-07-quint-architecture-verification` 第 6 节；评审流程 `4f0f34e0-25a0-4970-aba1-43db48a54fe3`。用户授权：“在完成对现有设计和模型的修复后对未评审内容进行评审、完善、适当进行验证”。独立源证据审计、只读设计评审与本次串行修订分别有署名角色及保留记录；后续最终独立门禁及父会话设计验收见第 6、7 节。

结论：原 ADR-008 补充及关联细化在下述 P1 修订后**技术设计已评审并接受**。这是一条新增评审记录，不改写 `architecture-v1` 与 ADR-001–006 的历史接受理由。ADR-007 **技术评审后保留为条件候选**，尚不能采用为已验证实现。数据、资源、兼容性、信任与平台条款的边界设计可接受；实际运行时验证仍未执行。终态人工 settlement、取消、恰好执行一次和新的权限体系继续排除。

## 1. 评审依据与来源身份

完整读取架构索引、术语及七份主契约，当前 PRD / design / implement 第 6 节、评审 intake、实际核心模型 / 测试 / 组合 / 恢复与修复日志。评审包括最初 ADR-008 的主体绑定、裁定、FIFO、finish / FailRun、生命周期及信任补充，未限定为最新的结果归约修复。

- 独立[源证据审计摘要](../quint/core/verification-report.md#source-decisions-and-model-corrections)：Ra v3.2.0、OTP-29.0 及实际 flake 选择；属于版本化源码证据，不是编译或故障测试。
- 独立[设计评审摘要](../quint/core/verification-report.md#source-decisions-and-model-corrections)：保留原作者逐项处置、P1 / P2 与验证边界；原始报告哈希及本地来源仅保存在 Git 忽略的证据目录中，新检出只能读取人工结果摘要。“待修订”属于修订前的原作者结论。
- 评审前来源哈希（本地专用、Git 忽略：`spec/quint/core/evidence/retained/pending-review/source-hashes-before.txt`；摘要见[核心报告](../quint/core/verification-report.md)）及最终来源哈希（本地专用、Git 忽略：`spec/quint/core/evidence/retained/pending-review/source-hashes-after.txt`；摘要见[核心报告](../quint/core/verification-report.md)）记录本次范围。本代理实际修订差异（本地专用、Git 忽略：`spec/quint/core/evidence/pending-design-review/lane-diff.patch`）从只读 HEAD 与开始时的 staged / unstaged 快照还原，已核对评审前哈希，不依赖刷新后的 index 来推断修改归属。原始修复反例与坏行为诊断继续保留，不作为修复通过证据。
- 复用身份检查（本地专用、Git 忽略：`spec/quint/core/evidence/retained/pending-review/reuse-identity.json`；摘要见[核心报告](../quint/core/verification-report.md)）独立重算实际可执行依赖；组合与恢复依赖未变，新测试使用自己的身份（本地专用、Git 忽略：`spec/quint/core/evidence/retained/pending-review/test-identity.txt`；摘要见[核心报告](../quint/core/verification-report.md)）与命令记录（本地专用、Git 忽略：`spec/quint/core/evidence/retained/pending-review/commands.json`；摘要见[核心报告](../quint/core/verification-report.md)）。

## 2. 发现与修订

<a id="p1"></a>

### P1：同一 Attempt 的迟到监视器报告缺少证据优先规则

修订前的[权威结果规则](./authority-and-recovery.md#3-契约)把 unknown 无条件写为未知阶段，而保留证据归约允许已验证 not_executed 解除该 Attempt。监视器先准备失联报告、原主体未执行证明先提交、具有不同 observation_id 的报告后到时，字面规则可能重新打开已解除的不确定性、追加通知并阻塞安全的新授权。这是源契约的顺序闭合缺口，不是已执行的核心反例或真实处理器故障。

处置：接受发现并修订。经本流程修订代理向父会话请求的[明确决定](../../.trellis/tasks/10-07-quint-architecture-verification/research/pending-monitor-supervisor.md)（ticket `b2de24cf-846f-4aa3-a72e-94be9b39e8fa`），同一不可变 Attempt 的有效确定原观测先提交后，迟到监视器失联报告仅保留审计来源，不覆盖确定观测、不改变既有 Effect / 终局结果、不重新引入已解除的 Attempt 未决条件，也不仅因报告迟到生成新通知。不同 observation_id 仍须正常验证，依据是证据含义而非仅按键去重。保留此前 unknown / 通知历史；局部失败仍可使逻辑操作未决，Recorded 不是逻辑结果证明。另一个已授权 Attempt 的失联独立处理。

修订位置：[监视器证据优先规则](./authority-and-recovery.md#monitor-evidence-order)、unknown 行、阶段说明、恢复责任、S4、[计算输入调度](./computation-and-effects.md#3-契约)、[I2 / I3 义务](./boundaries.md#interface-obligations)。明确修改的是 ADR-008 提议的顺序细化，保留基线的保守未知、真实观测、原主体及唯一结果保证。

实际核心的 `lose` 已只接受 Admitted，未改动作、归约、属性、init / step 或域。新增三个独立确定性测试：未执行证据后拒绝旧 Attempt 的 lose；局部失败仍未决且不重新通知；另一新 Attempt 仍可独立变为未知。测试检查实际事实与禁用动作，**不执行带不同键的排队监视器载荷，也不持久化该载荷的审计数据**。实际延迟报告 / 回复丢失 / distinct-ID / 审计追加的处理器验证归属 I2 / I3 与 S4；本记录没有以模型禁用动作冒充运行时行为。

<a id="p2"></a>

### P2：Ra API 引用版本与采用配置不够明确

处置：接受。ADR-007 的 process_command / consistent_query 链接固定为 v3.2.0，与 README / WAL 来源相同；命名 `wal_sync_method=none` 并要求承诺持久确认的采用配置拒绝该项。v3.2.0 `ra_system.erl` 接受 none，`ra_log_wal.erl` 的 `sync(_Fd, none)` 不同步；同步路径源码不证明端到端持久化法定人数行为。无可执行语义变化。

### 记录模式对应修订

已有失败声明补充要求求值时捕获声明引用、版本及生效失败含义，但 OperationDeclaration / 意图捕获 / Effect 意图表只列原重试字段。补齐这三处表格，与[失败声明](./capability-composition.md#failure-declaration)保持对应。没有增加协议行为、编码格式实现或通用声明框架；具体版本 / 载荷与兼容验证仍由 I3 / I4 承担。

## 3. 逐项技术处置与验证边界

| 项目与确切归属条款 | 技术设计处置 / 理由及替代取舍 | 已执行或检查的证据 | 未执行的运行时义务 / 暂缓事项 |
| --- | --- | --- | --- |
| 原主体绑定、重复分发、实例替换：[权威 §3 执行主体、分发与恢复](./authority-and-recovery.md#3-契约)、能力 §3 预检、边界 §3 工作进程 | 接受。实例身份与单调本地进入标记防止旧授权转移；主体丢失牺牲自动恢复进度，优于让替代进程继承无法确认的旧调用 | C1 / C2、重复分发及授权 / 主体变异、两种暂停顺序与迟到调用 | I3 的真实退出 / 任务重启 / 注册 / 标记 / 预检 / 替代进程测试；不保证外部恰好一次 |
| 保留证据与唯一终局结果：[权威结果规则及证据归约](./authority-and-recovery.md#evidence-reduction) | P1 修订后接受。成功在未终局前充分；其他 admitted / unknown 阻止失败；not_executed 仅解除自己的 Attempt；既有终局结果优先 | 真实 admitted、已本地完成未记录、迟到成功 / 非执行、局部失败回归及独立变异；P1 新禁用动作测试 | I2 / I3 的带键观测顺序、真实性、来源与审计持久保留；没有建立全文所有观测的模型 |
| 默认 / 版本化 / 持有提案捕获：[能力失败声明](./capability-composition.md#failure-declaration)、计算 §3 标识与捕获 / Effect 模式 | 接受，补齐模式表。默认 attempt_local 保守；logical_operation 是提供者需兑现的捕获契约，不从一般错误推导 | conclusive 布尔语义投影、持有声明 / 不可变 Effect 测试及变异 | I3 / I4 的真实注册表变更、精确版本、模式、兼容提供者与失败载荷符合性 |
| 当前计算 / 编排 / 原授权 / 一次许可：[权威权限表](./authority-and-recovery.md#evidence-reduction)、[外部控制器](./capability-composition.md#3-契约) | 接受。控制变更隔离新提案；原授权保留；审核、审计与 repeat 都不能绕过实际控制器。无需新权限框架 | 当前控制与 one-use 消费 / 重用变异；原授权晚进入 / 结果 | I2 的真实控制器替换、逐操作授权、execution_revision 与两个控制器竞争 |
| 回执原键与裁定竞态：[权威纪元与回执](./authority-and-recovery.md#3-契约)、[调用裁定](./authority-and-recovery.md#invocation-resolution)、信任 S16 | 接受。先接入授权、再查原回执、再检查当前条件；逻辑决策改变必须新键；settle / 观测提交顺序决定唯一终局 | settle / 迟到观测、一次许可及重复回复变异；完整接口表为源审查 | I2 的 command / observation / input 键冲突、原键重试、授权与错误优先级 |
| FIFO、通知与旧故障提案：[计算 §3 输入调度与游标](./computation-and-effects.md#3-契约)、S2 | P1 通知生成限定后接受。权威插入顺序避免来源优先级和跳队；过时 unknown 提案不能推进或 FailRun | 队首 / 通知 obsolete / 旧提案回归及 FIFO / stale 变异 | I2 的完整 input_id、通知身份与收件箱修复；不新增已存在非终局通知的处置行为 |
| 非法 finish、已确认故障与 failed 审计：[计算终态及审计](./computation-and-effects.md#failed-audit)、[生命周期只读前缀及终态审计](./lifecycle-and-archives.md#prefix-audit) | 接受。拒绝部分步骤与无限重试；failed 关闭新业务、admit、settle、repeat，却保留原授权 / 未知 / 迟到结果。修复业务从较早稳定边界分支 | failed / 局部失败 / 迟到结果、unprocessed 非 consumed、禁用恢复 / repeat / 业务消费变异 | I2 / I3 的真实故障 / 预算 / 宿主丢失区分与晚观测；终态人工 settlement、取消及自动清理证据暂缓 |
| 稳定前缀与独立分支：[生命周期 §3](./lifecycle-and-archives.md#3-契约)、S13 / S17 | 接受。资格在边界提交时记录；更早前缀不随源后续失败变化；新队列、身份和权限优于恢复源活动工作 | 源 / 分支组合、ready / finished 分支、前缀保留 / 继承授权变异 | I4 的完整前缀值、真实编码 / 资源 / 激活兼容；稳定性不证明旧物理主体停止 |
| 恢复所有者与进度：[权威已提交事实表](./authority-and-recovery.md#evidence-reduction)、[边界义务](./boundaries.md#interface-obligations) | 接受条件设计，监视器行按 P1 限定。各事实有模块与稳定重报身份；合法等待及可用性 / 调度前提明确 | 14 转换路径 / 严格递减 rank 与 restricted recovery depth14 NoError | 任意状态恢复 / 开放故障环境活性仍未建立；普通组合允许持续故障，不承诺必然成功 |
| 认证、信任与只读：[平台 §3 DTO 与授权、OTP 生命周期](./platforms-and-trust.md#3-契约)、S16 | 接受边界设计。有效 DTO / 校验和 / 只读查询不授予调用或代码加载权；Scope 和共识不是恶意成员沙箱 | 与回执及权限表交叉审查；I2 / I3 为显式前提 | 真正认证、授权、安全分布式接入与成员信任测试；第三方执行隔离暂缓 |
| ADR-007 与工具链：[条件采用门槛](./decisions.md#adr-007-review)、权威存储实现验证要求 | 条件候选；P2 已修订。单 Ra 组契合封闭命令状态机，比自行共识更合适；disk_log 是本地原语，Mnesia 仍需恢复 / 所有权契约 | v3.2.0 源码与 OTP26 / 27 支持列表、实际 flake OTP29 / Elixir1.20 选择；均非编译结果 | 固定实际采用版本、编译、跟随持久化 / quorum 确认 / 磁盘丢失 / 分区 / 快照 / 历史压缩 / 暂停竞态；不通过则重选实现，不降低基线保证 |
| Codec、资源、版本：[生命周期 ETF 数据配置](./lifecycle-and-archives.md#3-契约)、S18、边界 I4 | 接受约束，推迟实现验证。字节限制、safe + used、递归 / 模式检查与版本门槛职责清楚；堆限制不是严格 RSS 上限 | OTP-29.0 文档 / 源码的 safe、used、LOCAL_EXT、压缩、deterministic、max_heap_size 语义；归档权限模型 | ETF 往返 / 尾随 / 压缩 / local / 运行时对象拒绝、分配 / 超时 / 退出测量、生产默认预算与跨版本兼容 |
| 平台角色与支持：[平台矩阵及 S15](./platforms-and-trust.md#s15) | 接受目标与门槛，推迟实际支持声明。客户端与 Run 独立、角色配置与存储成员独立 | 与 I1–I4 / 信任 / 迟到授权一致性审查 | 真正 OTP / Elixir 打包、设备生命周期、网络与 provider 支持；README 和角色表不证明平台支持 |

<a id="adr-007-review"></a>

## 4. 条件采用与明确排除

本次没有拒绝 P1 / P2 的事实发现；两者已接受修订。没有采纳把 P1 扩展为完整监视器队列 / DTO / 审计模型的实现：现有核心禁用行为保留，实际延迟载荷义务明确交给 I2 / I3。没有新增通用模型、权限体系、终态裁定或运行时实现。限制范围不表示运行时义务已经完成，也不掩盖已确认的源顺序缺口。

Ra 文档支持候选性，不支持 OTP29 兼容或实际持久存储保证。ETF 文档支持边界要求，不支持已测量的解码器防护 / 平台兼容。ADR-007 在索引、决策与权威文档中均为条件候选；完成技术评审与采用验证分开记录。

## 5. 可执行证据及剩余界限

模型 SHA256：`7d98f1ff5ff4d31a2deb3d365d1b6bb6f4d5e3011d5af571e82eb5ade4044482`；composition：`ab9317006bd7465712c9aa04a802aaf8fa460aae31f66346087c7fc98f9fd73d`；recovery：`bb0101a96b58d926145b5324e1dac8869a610e9e73a9b2166b8c6af8957e0096`。本次均未变。已有修复独立门禁元数据（本地专用、Git 忽略：`spec/quint/core/evidence/retained/composition/metadata.json`；摘要见[核心报告](../quint/core/verification-report.md)）及原日志与实际身份匹配，因此复用而不重复昂贵检查。

- 先前六项 typecheck、43 项测试（25 正例 / 18 检测变异）、14 转换恢复路径与 24 转换组合已执行。本次新增测试文件 typecheck 和三个限定回归通过；当前[全部 46 项测试](../quint/core/verification-report.md#source-decisions-and-model-corrections)通过（28 正例 / 18 检测变异）。精确命令、exit 与新测试身份另存；首次测试书写中 fail 后读取未赋值状态的 QNT502 已保留为开发诊断，调整断言位置后通过，未改变核心模型。
- 复用默认 composition.init / step / safety、Runs0/1、每 Run 一个 Effect、Attempts0/1、owners0/1、FIFO6 的 10,000 depth60 样本；seed 参数 20261014、复现 0x35e178f，无采样反例。十个非初始 witness 均正：1791 / 139 / 225 / 158 / 5 / 1 / 567 / 16 / 10 / 5；消费与恢复消费仍稀疏，不构成 P1 排队报告覆盖。
- 复用实际所有动作 depth10、random-transitions=false、240 秒 / port8863 尝试：exit124、240.054 秒、检查 State5 时超时。**完整组合请求界限及任何较小界限均未建立**，没有把 StateK 当证明。受限 recovery.init / step / safety + premises / rankDecreases、Run0 / FIFO4、depth14、120 秒 / port8864 完成 NoError；仅适用于其明确可用性、合法步骤、成功替代主体、repeat、容量、无额外干扰与最终调度前提。

核心仍不包含完整 command / receipt / observation / input 键表、DTO / 错误优先级、真实绑定代次 / Scope / 授权内部、声明版本和提供者符合性、审计载荷历史、Ra / ETF / 设备实现或一般活性。I1–I4 是接口前提。有限身份 / 队列与 opaque 前缀限制保持；历史详细模型缺口和反例不被本记录关闭。

本次[最终来源 / 链接 / 语法 / 空白 / index 身份检查](../quint/core/verification-report.md#source-decisions-and-model-corrections)提供源检查证据。没有安装、编译运行时、启动后端、改变 flake、暂存或提交；原 dirty 工作与历史证据保留。本代理未执行任何 Git 修改命令；实际 index 指纹发生刷新（初始 `d3beae8a…`，观察到 `5ed7da90…`），不推断自动 hook 的归因、不还原当前 index，最终身份另存。此记录完成技术处置及串行修订，最终独立检查、父会话验收、规范综合、提交与生命周期仍由父会话负责。

<a id="final-independent-check"></a>

## 6. 最终独立检查归属

流程 `4f0f34e0-25a0-4970-aba1-43db48a54fe3` 的 `trellis-check` 最终检查已完成，独立读取最终主契约全文、原始只读评审发现及实际模型 / 测试 / 日志，并重算来源身份。结论：P1 / P2 及捕获模式对应修订均已落实；原 ADR-008 补充与关联细化没有已知剩余范围内设计阻塞，建议通过本次设计质量门禁。父会话仍负责最终验收与生命周期；本节不修改前述修订代理的历史记录或关闭运行时义务。

最终检查重新执行 core_test typecheck 及全部 46 项测试（28 正例 / 18 检测变异），exit0。七项复用可执行依赖与旧修复证据逐项匹配；修订代理的 22 项来源 / 测试身份在本次归属文字更新前均匹配。新记录的最终文档身份与原模型证据分别保存于最终检查证据（本地专用、Git 忽略：`spec/quint/core/evidence/retained/final-check/final-validation.json`；摘要见[核心报告](../quint/core/verification-report.md)）；没有语义模型变化或昂贵检查重复。

独立重新获取并检查 Ra v3.2.0 与 OTP-29.0 的 API、WAL / 配置 / README、safe / used / LOCAL_EXT / deterministic / heap 相关源码段落及完整下载哈希，见版本化来源记录（本地专用、Git 忽略：`spec/quint/core/evidence/retained/external/sources.json`；摘要见[核心报告](../quint/core/verification-report.md)）。这些仍只是源码证据；没有安装、编译、运行 Ra / OTP 存储或编码器。

P1 的三个测试仍仅为模型事实与旧 lose 禁用检查；不同键排队报告及审计持久化继续归属 I2 / I3 / S4。复用的 10,000 depth60 样本无采样反例、十个 witness 正值；完整组合 depth10 的 240 秒 timeout124 / State5 仍不确定，不能建立任何较小界限。受限恢复 depth14 NoError 仅覆盖明确调度。真实 Ra / quorum / 磁盘 / 授权 / 进程 / 提供者 / 版本 / ETF / 资源 / 平台验证，以及 OTP29 / Elixir1.20 候选构建均未完成。ADR-007 保持条件候选，终态人工 settlement 继续暂缓。

<a id="parent-acceptance"></a>

## 7. 父会话设计验收

父会话已消费本流程四份完整报告，核对 P1 / P2 与捕获模式对应修订、逐项技术处置及实际证据，并独立重算最终检查的 22 项来源 / 测试身份、7 项复用依赖，与保留日志一致；ADR-001–006 与 HEAD 的历史文字保持。接受本次范围内设计质量门禁及 ADR-008 技术设计，未发现剩余范围内设计阻塞。ADR-007 仍为条件候选，终态人工 settlement 仍暂缓。

46 项检查、10,000 条默认组合 depth60 抽样与十个正 witness 的证据保持；抽样不构成证明。完整组合 depth10 的 240 秒 timeout124 / State5 仍无结论，受限恢复 depth14 NoError 仅覆盖明确调度。I1–I4、真实不同键监视器排队 / 审计、OTP29 / Elixir1.20 构建、Ra / ETF / 资源 / 平台验证均未执行。技术验收不关闭这些义务或历史详细模型缺口。

父会话仅补充验收归属及 Trellis 验证规范经验；未改可执行模型、核心测试或旧证据。补充测试文件只移除末尾多余空行，历史来源身份仍按原运行保留。父会话最终来源检查（本地专用、Git 忽略：`spec/quint/core/evidence/retained/parent-acceptance/final-validation.json`；摘要见[核心报告](../quint/core/verification-report.md)）单独记录验收文字后的身份与检查范围；原始日志、补丁及源码摘录不作空白规范化。提交与任务生命周期另行处理，本记录不宣称任务归档或完整形式 / 运行时验收。
