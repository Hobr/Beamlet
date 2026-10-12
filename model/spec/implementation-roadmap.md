# 按依赖组织的实现路线

状态: 后续实现的建议路线, 不是已经执行的任务记录. 当前继续收敛架构与 SPEC, 未授权生成 Runtime 代码.
各阶段完成条件是必须取得的证据, 不因现有 Quint 场景通过而自动标记完成.
范围见 [首版范围](first-release-scope.md), 组件边界见 [整体架构](runtime-architecture.md).

## 1. 依赖顺序

```mermaid
flowchart LR
    D0["0: 契约与实现前选择"] --> D1["1: 领域规则与值"]
    D1 --> D2["2: 真实 Storage"]
    D2 --> D3["3: 本地执行闭环"]
    D3 --> D4["4: 远端 Worker"]
    D3 --> D5["5: Pending 与恢复"]
    D4 --> D6["6: 调用方组合与首版验收"]
    D5 --> D6
```

| 阶段 | 交付物 | 完成条件 |
| --- | --- | --- |
| 0. 契约与选择 | 公开领域类型与错误分类草图, 后端/驱动与协议选择, 资源绑定和 History 编码方案 | 区分已确认决策与建议, 所有必须项可追溯到 SPEC; 未决项有边界, 不默认使用任意 term/内存 Authority |
| 1. 领域规则与受限值 | IEO, 资格/证据/停止规则, 定义相等与值域验证, History 逻辑材料 | 无 Repo/网络/进程依赖; 原子接受, Unknown/旧成功阻塞等场景对应代码测试; 数值/Unicode/预算边界可测 |
| 2. Storage 与后端符合性 | 原子命令, 一致读取, 物理约束与 History 映射; SQLite/PostgreSQL Adapter | 两个真实后端分别通过提交/领取/授权/报告/终结竞争, 回滚, 响应丢失重投, 保护内取时; 不以 Memory 假实现替代 |
| 3. 本地执行闭环 | Coordinator, 持久扫描, Worker 会话, 同步示例 Handler, 查询/结果复用入口 | 完整 Submit 到 ReadFacts 路径; 通知全丢仍发现工作, 重启不重复旧调用; Unknown 不能由超时变 Failed |
| 4. 跨设备执行 | 一个选定 Transport 的版本化消息, 可信身份, 重连/路由, 环境匹配与资源约束 | 两种部署形态验证; 错 scope/旧会话拒绝; 授权回复/报告丢失恢复; 设备资源不能被同名替换; 未获许可的分区 Worker 不新调用 |
| 5. Pending 与恢复 | 持久完成关联, 回调 Adapter/发送者保留或 inbox, 能力查询和安全重试 | 完成先于 Pending, 原 Worker 丢失后完成; 验签/账户/重复/冲突测试; 原幂等窗口和旧协议不能被升级延长/改义 |
| 6. 调用方组合与交付 | 稳定提交与事实读取便利层, 多 Agent/Tool Call 验收, 部署与兼容性说明 | 原依赖清单恢复部分结果/汇总; 两 Intent 隔离与共享 Worker 重启; 两后端完整验收, 旧数据读取和明确未支持边界 |

一个 SQL 后端可先用于打通闭环, 另一后端可随后并行实现; 正式首版宣称双后端支持前必须都达到阶段 2/6 的符合性要求.
阶段 4 与 5 可以并行推进, 但共享消息/绑定接口必须先收敛. 简单 sync Handler 可先实现, 不能因此宣称长等待已支持.
LLM, 文件, Browser/Device 的正式支持分别取决于其版本化 Operation/Adapter 验收, 核心闭环通过不自动批准所有 provider.

## 2. 实现前必须选择的事项

以下属于实现方案, 不重新讨论已确认的 Unknown, 唯一 Outcome 和授权先于调用等安全约束:

- 公开 API/Behaviour 的最小签名, principal/权限上下文和错误分类, 同步等待超时的返回语义.
- 首个 Transport, 可信身份映射, 协议/codec 版本协商, 连接限制与应用重投; 不强制 Distributed Erlang.
- Ecto/驱动/数据库版本, 事务隔离/锁形式与 durable 配置; SQLite 不跨设备共享文件.
- History 的记录身份, 提交组/次序表示与字段预算, 非复用/耗尽行为及分页权限.
- Worker incarnation 编码, 资源身份/权限验证与 Handler 登记配置; 无安全依据的配置不进入授权路径.
- 首批示例 Operation 的外部协议: 至少一类同步操作与一类 Pending 操作; 执行成本与测试隔离.

动态成员注册, 全局调度公平性, 手工协调, 规则治理, 迁移和归档不阻塞首版小闭环, 也不允许以它们后置为由放宽守卫.
进程树, 连接池和扫描频率可以从简单方案开始, 但不把部署中的单进程假设当作并发证明.

### 2.1 研究收口的确认清单

下表区分已确认的逻辑/模型范围与后续实现选项, 不因补文档自动批准物理设计或依赖. 已确认的唯一 Outcome, Unknown 不等于
Failure, 授权先于调用和调用方拥有业务上下文不重开讨论.

| 项目 | 最小建议与替代方案 | 确认/验证门槛 |
| --- | --- | --- |
| 部分推进 | 先验证 A/B 的一项 Success 驱动 C; 调用方保存单步决定与下一步定义/key. 替代为每次重启重新算, 需额外确定性与重复决策依据 | 三 Intent/两轮/一个持久决定槽的模型形状已确认并加入检查; 见 [组合契约](multi-intent-and-tool-calls.md), 不批准任意业务决策引擎 |
| History 逻辑次序 | 同 Intent 提交组与组内位置, 不设全局序列或用墙钟仲裁. 替代为仅时间戳, 无法解释回拨及并发次序 | 逻辑材料与最小模型形状已确认; 有界模型检查原子关联与非复用; 编码/耗尽与物理计数在阶段 0 选 |
| 资源绑定 | 不可变逻辑目标+授权时具体绑定+调用前重验, 静态可信配置可起步. 仅节点标签/同名路径不能替代目标身份 | 最小绑定形状已确认; 有界模型检查错设备/目标与原解释稳定, 不引入通用资源注册平台 |
| 代表 Operation | 先选一类同步与一类审批 Pending; 文件/Device 样例仅说明声明条件. 不把所有 provider 列为默认支持 | 审阅 [Operation 样例](operation-handler-contracts.md) 的结果含义与外部证明义务 |
| 公开 Interface | 保留稳定身份, 持久确认/结果接受和拒绝/存储不确定性区分, 不暴露 CRUD 拼事务 | 审阅 [存储材料与错误](storage-command-contracts.md); 最终 Elixir/wire 签名在阶段 0 定 |
| Transport/驱动 | 可由后续实现选型, 但须保留可信作用域, 命令重投及两个 SQL 后端符合性 | 网络集成/SQL 开发前锁定版本与配置, 不是现在增加依赖的授权 |
| Skuld 身份 | 保持候选比较; 不以同名项目或未经审计版本作基础设施保证 | 若需正式选型, 项目方确认 URL/版本后限定审计; 不阻塞独立 Effect 核心研究 |

部分推进与五项补验的状态形状均已确认并补入模型, 包括领取回复丢失, 资源匹配, History 提交关联,
三原始并发依赖恢复与共享资源条件写. 各项有确定场景, 独立 mutation 和有正见证的有限采样,
不据此扩大核心为 Workflow 或完整产品模型.
上述顺序是研究补验路线, 不改变第 1 节后续 Runtime 的依赖顺序.

### 2.2 本轮补验的最小状态形状

状态: 五项最小状态形状已确认, 独立可执行模型与检查已接入. 实际数量, 采样与证据边界见 [覆盖记录](../quint/coverage.md).
复用现有纯规则和完整执行账本, 保留旧入口, 场景与 mutation. 每项独立实例, 不构造五项的全状态积.
普通命令仍以同 Intent 的权威事务为原子边界; 网络, 调用方存储与外部资源均不加入该事务.

| 补验 | 状态所有者与最小材料 | 有界实例与原子粒度 | 关键性质与负例 |
| --- | --- | --- | --- |
| Claim 回复丢失 | 原 execution ledger/Worker local; 额外无序 Claim 请求/回复集合. 请求含 execution/worker/incarnation/expected generation, 原分配关联 request -> token, Worker 仅记录已收到 token | 一 Intent, 两 Worker/Execution, generation 至多 3. 请求发送, 权威领取提交, 回复送达分别为动作; 同旧 expected generation 的重投不重新领取 | 原分配稳定, 回复前本地不获 token, 旧回复不带来新授权; 换 token/新代, 跨会话回复, 抢占重投的独立负例 |
| 资源匹配 | 原正常执行账本; 实际环境的设备/账户/可访问对象与协议映射, 启动时不可变 binding, 独立实际调用记录 | 一 Intent, 两 Worker/目标/账户与两个解释版本. 两设备可有同一路径但不同对象; 授权与外部调用之间允许配置变化, 调用使用确切快照目标而非当前默认值 | 错目标不授权/不调用, 换 Worker 不换逻辑资源, 升级不换账户/协议; 默认设备或账户替换, 快照改写负例 |
| History 提交关联 | 原执行持久事实; 每 Intent 已提交组和事实列表, 两 Coordinator 的易失事务草稿. 事实关联实体, 前后修改, 主体/原因/解释版本, 记录时钟是诊断值 | 一 Intent, 两 Execution/Coordinator, 抽象提交组至多 6. 事务草稿不可被 ReadFacts 看到; commit 同步公开状态和对应事实, crash/rollback 丢草稿但不丢已提交材料 | 提交组与组内位置唯一, 已提交次序不因回拨改变, 无孤立状态/审计, 重投不重复记录; 分裂写入, 复用提交组, 重复审计负例 |
| 三并发依赖恢复 | 原 multiStore/callerRounds/agentLocals 等状态, 单轮完整三 slot manifest, 不增加持久决策槽 | 三 Intent, 一轮, 一个调用方, 两 Worker/Execution. A/B/C 都从原轮次提交而非由 A 驱动 C; 已终结两项后清空易失 Agent 状态 | 重建三项原关联, 仅两项不能汇总, 最后一项可晚到/Unknown, 已完成结果不重新执行; 丢第三 slot, 按两项数量完成, 重建时换 key 负例 |
| 共享资源条件写 | 两个独立 Intent ledger; 一份外部对象 version/content, 按对象/account/Operation/原 key 绑定的 receipt, 实际写入与报告证据 | 两 Intent, 一个对象, 每 Intent 至多两 Execution, 一个可竞争的初始版本. 外部 CAS 与 receipt 同资源事务, 与 Beamlet Report/Outcome 提交分开 | 同初始版本至多一项 applied, version_mismatch 是正常 Success 数据, 重放原 key 不再次写入, 不借另一 Intent 的 receipt 证明自己完成; 双写, 跨 key 借回执, 按当前内容猜完成负例 |

Claim 的原分配关联是逻辑材料, 可以由现有 lease/身份事实推导或记录; 不自动批准新增 SQL 表.
迟到 Claim 回复可以携带已经失效的旧 token, 接收不等于有效权限; 启动仍需当前权威守卫, 不假装 Worker 知道瞬时远端状态.
资源匹配不宣称一次本地预检查能锁住外部世界. 调用必须携带明确目标/账户, 对象版本等强条件由实际资源协议保障.
History 例子优先选创建/领取/授权/报告/终结与重复报告, 不声称有限组能覆盖任意审计事件序列.
两个 Coordinator 不能各自持有可绕过重验的写入权; 草稿在 commit 时须仍满足原快照/守卫, 失败则回滚或重读.
History 只要求已提交组身份不复用; 未提交, 从未公开的草稿组可以丢弃, 不给诊断时钟授权含义.
三并发例子仍只验证持久依赖恢复, 不恢复 Agent 栈, 不引入通用 DAG 或 await_any/quorum 的所有策略.
共享资源例子选择支持原子 CAS + 请求绑定 receipt 的资源协议, 不是断言普通文件系统或 Browser 天生支持它;
缺少这些前提的 Operation 仍可用较弱契约并保留 Unknown. 该前提也不是 Beamlet 的通用 exactly-once 保证.

各项按类型/初始化, 守卫/更新, 薄动作, 确定场景, 独立反例与有限采样实施; 旧入口, 场景和 BUG 编号保留.
本轮补验不增加 Runtime/Ecto 实现, 后续仍须用真实存储, 资源服务和故障注入检验模型前提.

## 3. 规格与实现如何互证

1. 从关键 SPEC 行为选择验收场景, 将领域纯决策与 Quint 守卫/转换对应; 不要求把验证快照照搬为产品 schema.
2. 用真实 SQL 竞争, 故障注入和消息测试检验模型的原子性/可信入口前提, 记录依赖版本和部署条件.
3. 如果发现不一致, 先判定实现错误, 规格遗漏或抽象边界, 不为通过测试静默削弱安全规则.
4. 修改启动/重试/证据/终结语义时, 同步更新场景, 独立性质及 mutation; 有限采样不表述为普遍正确性证明.
5. 所有对外能力标明支持范围: 业务资源, 恢复材料, 幂等/查询条件, 以及不可自动恢复的 Unknown.

文档整理只检查链接与一致性; 核心语义修改跑相关 Quint 场景/反例和定向模拟, 跨层改动再完整回归.
运行日志和故障轨迹写入指定产物目录, 不继续添加阶段性 Markdown 日志.

## 4. 与原始目标的对应

| prompt.md 预期结果 | 阅读位置 |
| --- | --- |
| 整体架构, 分布式角色与替换边界 | [整体架构](runtime-architecture.md) |
| 领域选择与替代方案/研究依据 | [核心理由](../rfc/0001-core-boundaries.md), [方案对照](../rfc/0002-runtime-tradeoffs.md) |
| 状态机, Outcome, History | [核心状态机](core-state-machines.md) |
| 恢复, 环境与长等待协议 | [lease](leases-and-permissions.md), [Handler/恢复](handler-recovery-contracts.md) |
| Storage Behaviour 义务与 Ecto 双后端 | [存储命令](storage-command-contracts.md), 整体架构的组件契约 |
| 值, 身份和兼容解释 | [值与消息](persistent-values-and-messages.md), [Operation](operation-handler-contracts.md) |
| 并发依赖与调用方恢复边界 | [多 Intent](multi-intent-and-tool-calls.md) |
| 不变量, Quint 证据与未覆盖项 | [模型覆盖](../quint/coverage.md) |
| 阶段依赖和完成条件 | 本文 |

这些文档足以组织首版实现讨论, 不表示尚待选择的物理接口已获批准, 或真实后端/资源契约已经通过验收.
