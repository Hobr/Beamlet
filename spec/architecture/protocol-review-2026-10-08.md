# 协议补充技术评审

<a id="disposition"></a>

ADR-008 的执行主体、调用裁定、FIFO、finish/FailRun 与关联细化已接受为技术设计。`architecture-v1` 与 ADR-001–006 的历史理由保持；ADR-007 中 Ra 保留为条件候选。设计接受与模型证据、运行时采用验证分开，完整组合 depth10 尚无结论，I1–I4 尚待实现测试。

## 发现与修订

<a id="p1"></a>

### 同一 Attempt 的监视器证据优先规则

旧 unknown 行缺少顺序条件：原主体的有效 not_executed 已提交后，另一 observation_id 的迟到失联报告可能重开不确定性、追加通知并阻塞新授权。该发现是源契约闭合缺口，未被宣称为真实处理器故障。

[证据优先规则](./authority-and-recovery.md#monitor-evidence-order)明确：同一 Attempt 已有经过验证的确定原观测后，迟到监视器报告仅追加有来源审计，不覆盖观测、改变既有 Effect/结果、重开已解除的未决条件或重新通知。仍验证来源、原授权、绑定、数据与键冲突；局部失败仍可逻辑未决，另一 Attempt 的失联独立处理。该规则同步到通知生成、恢复职责、S4 和 I2/I3。

核心 `lose` 只接受 Admitted。三个确定性回归检查：未执行证明后拒绝旧 lose；局部失败仍未决且拒绝旧 lose；新 Attempt 可以独立 unknown。这些是模型事实和 guard 检查，未投递不同键的排队监视器载荷，也未验证其审计持久化，实际义务仍归属 I2/I3/S4。

### Ra 引用与持久确认配置

ADR-007 的 process_command、consistent_query、WAL 与配置引用固定为 Ra v3.2.0。该配置接受 `wal_sync_method=none`，其同步函数不执行磁盘同步；承诺持久确认的采用配置必须拒绝此项。WAL 同步路径源码只支持候选评估，不能证明端到端持久化法定人数确认或 OTP29 兼容。

### 捕获声明的记录模式

OperationDeclaration、意图捕获与 Effect 意图表补齐声明引用、契约版本及生效失败含义，与[失败声明](./capability-composition.md#failure-declaration)对应。默认 attempt_local 保守；logical_operation 只能由真实操作契约支持。精确版本、载荷与提供者兼容仍由 I3/I4 验证。

## 逐项技术处置

| 项目与确切归属条款 | 技术设计处置 / 理由及替代取舍 | 已执行或检查的证据 | 未执行的运行时义务 / 暂缓事项 |
| --- | --- | --- | --- |
| 原主体绑定、重复分发、实例替换：[权威 §3 执行主体、分发与恢复](./authority-and-recovery.md#3-契约)、能力 §3 预检、边界 §3 工作进程 | 接受。实例身份与单调本地进入标记防止旧授权转移；主体丢失牺牲自动恢复进度，优于让替代进程继承无法确认的旧调用 | C1 / C2、重复分发及授权 / 主体变异、两种暂停顺序与迟到调用 | I3 的真实退出 / 任务重启 / 注册 / 标记 / 预检 / 替代进程测试；不保证外部恰好一次 |
| 保留证据与唯一终局结果：[权威结果规则及证据归约](./authority-and-recovery.md#evidence-reduction) | 证据优先规则修订后接受。成功在未终局前充分；其他 admitted / unknown 阻止失败；not_executed 仅解除自己的 Attempt；既有终局结果优先 | admitted 前态、已本地完成未记录、迟到成功 / 非执行、局部失败回归及独立变异；监视器禁用动作测试 | I2 / I3 的带键观测顺序、真实性、来源与审计持久保留；没有建立全文所有观测的模型 |
| 默认 / 版本化 / 持有提案捕获：[能力失败声明](./capability-composition.md#failure-declaration)、计算 §3 标识与捕获 / Effect 模式 | 接受，补齐模式表。默认 attempt_local 保守；logical_operation 是提供者需兑现的捕获契约，不从一般错误推导 | conclusive 布尔语义投影、持有声明 / 不可变 Effect 测试及变异 | I3 / I4 的真实注册表变更、精确版本、模式、兼容提供者与失败载荷符合性 |
| 当前计算 / 编排 / 原授权 / 一次许可：[权威权限表](./authority-and-recovery.md#evidence-reduction)、[外部控制器](./capability-composition.md#3-契约) | 接受。控制变更隔离新提案；原授权保留；审核、审计与 repeat 都不能绕过实际控制器。无需新权限框架 | 当前控制与 one-use 消费 / 重用变异；原授权晚进入 / 结果 | I2 的真实控制器替换、逐操作授权、execution_revision 与两个控制器竞争 |
| 回执原键与裁定竞态：[权威纪元与回执](./authority-and-recovery.md#3-契约)、[调用裁定](./authority-and-recovery.md#invocation-resolution)、信任 S16 | 接受。先接入授权、再查原回执、再检查当前条件；逻辑决策改变必须新键；settle / 观测提交顺序决定唯一终局 | settle / 迟到观测、一次许可及重复回复变异；完整接口表为源审查 | I2 的 command / observation / input 键冲突、原键重试、授权与错误优先级 |
| FIFO、通知与旧故障提案：[计算 §3 输入调度与游标](./computation-and-effects.md#3-契约)、S2 | 通知生成条件限定后接受。权威插入顺序避免来源优先级和跳队；过时 unknown 提案不能推进或 FailRun | 队首 / 通知 obsolete / 旧提案回归及 FIFO / stale 变异 | I2 的完整 input_id、通知身份与收件箱修复；不新增已存在非终局通知的处置行为 |
| 非法 finish、已确认故障与 failed 审计：[计算终态及审计](./computation-and-effects.md#failed-audit)、[生命周期只读前缀及终态审计](./lifecycle-and-archives.md#prefix-audit) | 接受。拒绝部分步骤与无限重试；failed 关闭新业务、admit、settle、repeat，却保留原授权 / 未知 / 迟到结果。修复业务从较早稳定边界分支 | failed / 局部失败 / 迟到结果、unprocessed 非 consumed、禁用恢复 / repeat / 业务消费变异 | I2 / I3 的真实故障 / 预算 / 宿主丢失区分与晚观测；终态人工 settlement、取消及自动清理证据暂缓 |
| 稳定前缀与独立分支：[生命周期 §3](./lifecycle-and-archives.md#3-契约)、S13 / S17 | 接受。资格在边界提交时记录；更早前缀不随源后续失败变化；新队列、身份和权限优于恢复源活动工作 | 源 / 分支组合、ready / finished 分支、前缀保留 / 继承授权变异 | I4 的完整前缀值、真实编码 / 资源 / 激活兼容；稳定性不证明旧物理主体停止 |
| 恢复所有者与进度：[权威已提交事实表](./authority-and-recovery.md#evidence-reduction)、[边界义务](./boundaries.md#interface-obligations) | 接受条件设计，监视器遵循证据优先规则。各事实有模块与稳定重报身份；合法等待及可用性 / 调度前提明确 | 14 转换路径 / 严格递减 rank 与 restricted recovery depth14 NoError | 任意状态恢复 / 开放故障环境活性仍未建立；普通组合允许持续故障，不承诺必然成功 |
| 认证、信任与只读：[平台 §3 DTO 与授权、OTP 生命周期](./platforms-and-trust.md#3-契约)、S16 | 接受边界设计。有效 DTO / 校验和 / 只读查询不授予调用或代码加载权；Scope 和共识不是恶意成员沙箱 | 与回执及权限表交叉审查；I2 / I3 为显式前提 | 真正认证、授权、安全分布式接入与成员信任测试；第三方执行隔离暂缓 |
| ADR-007 与工具链：[条件采用门槛](./decisions.md#adr-007-review)、权威存储实现验证要求 | 条件候选；引用与配置要求明确。单 Ra 组契合封闭命令状态机，比自行共识更合适；disk_log 是本地原语，Mnesia 仍需恢复 / 所有权契约 | v3.2.0 源码与 OTP26 / 27 支持列表、实际 flake OTP29 / Elixir1.20 选择；均非编译结果 | 固定实际采用版本、编译、跟随持久化 / quorum 确认 / 磁盘丢失 / 分区 / 快照 / 历史压缩 / 暂停竞态；不通过则重选实现，不降低基线保证 |
| Codec、资源、版本：[生命周期 ETF 数据配置](./lifecycle-and-archives.md#3-契约)、S18、边界 I4 | 接受约束，推迟实现验证。字节限制、safe + used、递归 / 模式检查与版本门槛职责清楚；堆限制不是严格 RSS 上限 | OTP-29.0 文档 / 源码的 safe、used、LOCAL_EXT、压缩、deterministic、max_heap_size 语义；归档权限模型 | ETF 往返 / 尾随 / 压缩 / local / 运行时对象拒绝、分配 / 超时 / 退出测量、生产默认预算与跨版本兼容 |
| 平台角色与支持：[平台矩阵及 S15](./platforms-and-trust.md#s15) | 接受目标与门槛，推迟实际支持声明。客户端与 Run 独立、角色配置与存储成员独立 | 与 I1–I4 / 信任 / 迟到授权一致性审查 | 真正 OTP / Elixir 打包、设备生命周期、网络与 provider 支持；README 和角色表不证明平台支持 |

<a id="adr-007-review"></a>

## 条件实现与替代方案

Ra 的封闭命令状态机契合单权威组方案，采用前必须验证实际工具链构建、跟随节点持久化、quorum 应用与回复、回执丢失、快照与历史压缩、磁盘丢失、分区及暂停竞态。v3.2.0 README 列出 OTP26/27，项目选择 OTP29/Elixir1.20，兼容性尚未验证。disk_log 是本地原语；Mnesia 仍需要应用恢复与所有权契约。不通过采用验证时重新选择实现，不能降低已接受保证。具体来源与要求见[ADR-007](./decisions.md#adr-007-review)。

ETF 的 safe/used、压缩、LOCAL_EXT、deterministic 与 max_heap_size 文档支持[数据边界要求](./lifecycle-and-archives.md#3-契约)，不证明解码器防护已测量。字节限制、有界工作进程、递归模式检查与完整字节消费各有独立作用；堆预算不是严格 RSS 保证，跨 OTP 逻辑相等也不意味着规范字节相等。

终态人工 settlement、取消、外部恰好执行一次、恶意成员隔离与执行中分支不属于初始契约。

## 模型结果与限制

[核心报告](../quint/core/verification-report.md)记录六项 typecheck、46项测试（28正例/18检测变异）、14转换恢复路径、24转换代表组合及10,000条默认组合抽样。组合为 Runs0/1、每 Run 一个 Effect、每 Effect 两个 Attempt、两个主体、FIFO6；depth60、seed20261014，无采样反例，十个 witness 均正。消费5次、同一 Run 的恢复消费1次仍稀疏。

完整组合 depth10、所有动作、默认 init/step/safety、random-transitions=false，240秒预算在 State5 超时，exit124；请求界限及任何较小界限均未建立。受限恢复 Run0/FIFO4、depth14、safety/premises/rankDecreases 完成 NoError，只适用于明确可用性、合法步骤、成功替代主体、repeat、容量、无新增干扰与最终调度前提。上述抽样/BMC 是已有结果，文档整理没有新运行或新形式证明。

核心不展开完整命令/回执/输入/观测键表、DTO、错误优先级、真实绑定/资源/授权内部、审计载荷历史或 Ra/ETF/设备实现。技术评审不能关闭[I1–I4 实现义务](./boundaries.md#interface-obligations)；监视器回归的 guard 检查不能替代真实延迟报告与审计测试。
