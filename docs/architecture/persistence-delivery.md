# 持久化实施与验收计划

状态：核心方向及“历史记录 + 检查点”两原语、fork 创建新 Agent 的方案已获用户同意。本计划仍仅为文档，不实施、不添加依赖、不创建/激活新的 Trellis 实现任务。

本计划对应[主设计](./agent-operation-persistence.md)与[术语](../../GLOSSARY.md)。实现需要在后续独立任务中确认范围；下列验收是未来必须取得的证据，不是已经运行的测试。

## 1. 需求追踪

| 需求 | 设计位置 | 验收证据 |
| --- | --- | --- |
| Agent / Operation 持久化 | 主设计 3–6 | 两库事务失败时无部分业务事实，成功提交在 VM 重启后可读 |
| Ecto，SQLite 默认 / PostgreSQL 可选 | 3.1、11 | 两种实际数据库运行同一存储契约，选定 Repo 与连接设置被核查 |
| 权威保存业务事实 | 1、5、6 | executor 不访问权威 DB；authority-only 可以审阅/恢复 |
| 执行节点可靠性日志 | 6.3 | 完成后权威断连，重启/重连可取回相同证据，handler 调用计数不增加 |
| 禁止 PID / 闭包等 | 4 | 所有写入口拒绝嵌套活对象，无 external term 漏口 |
| 恢复 | 7 | 从每个继续位置恢复为 paused，明确继续后无重复派发/消费 |
| 历史审阅 | 8 | 无活进程/超出 Runtime retention 仍可查询完整业务历史 |
| 轨迹导出 | 8 | 固定高水位，复制上下文及其来源、artifact、digest 与未包含项可验证，无需追溯父链 |
| 回撤 | 9 | 新 Agent ID、独立上下文、原历史不变，旧结果不推进新 Agent，未决环境风险默认禁止继续 |
| 不做共识/故障转移 | 1、7 | 无跨权威自动接管；同 authority 独占要求写入部署说明 |
| 不撤销外部改变 | 9、12 | 回撤后模拟环境已发生的改变仍存在，展示文案不承诺撤销 |
| 保持单 attempt、不自动重试 | 6、7 | 每个崩溃切点的 handler 调用总数不因恢复而增加 |
| 展示与业务事实分离 | 2、3.3、6 | display 截断/省略、订阅丢弃不影响完整历史、检查点、恢复和 fork |
| 停止原因与终止观察保真 | 5、6.3–6.4、12 | 首个停止触发原因不被竞争请求覆盖，正常返回/无关崩溃不被重分类，重启不伪造停止 |
| 注册就绪不等于持久准入 | 3.3、11 | Repo/Node 保持注册时注入写失败仍禁止相应输入/派发，观察接口不授权执行 |

## 2. 推荐实施阶段

### A. 持久数据契约和存储基础

产物：`beamlet_storage` 的具体存储函数、严格 codec、身份与版本契约、双 Repo 选择、authority/journal 分离迁移、Ecto.Multi 事务、artifact 与对象内历史序号、分页查询。不增加通用 bundle/Document/Storage behaviour。

验收：SQLite / PostgreSQL 各自使用真实数据库；完整 Ecto.Multi 回滚；同 command 同参数幂等、不同参数冲突；CAS 竞争与连续流序号；所有非法活对象/深度/大小/秘密字段规则；迁移/重启/旧新版本/恢复标记拒绝；artifact 引用原子性；库加载不启动角色。阶段 A 已取得实际证据（双库 64 用例、全伞 281 用例、dialyzer 0 error），见 `10-18-durable-storage/research/a-verification.md`；物理表数为权威 8 业务 + 1 安装元数据，日志 1 + 1，另加各自迁移版本表；锁定等待由驱动 busy handler 提供，不以 `PRAGMA busy_timeout` 回读值作为依据。

此阶段不接入真实模型/Tool，不声称恢复业务。首版不提取通用对象存储或插件式数据库框架。

### B. 通用 Runtime 的权威记录及执行日志

依赖 A。产物：稳定 attempt ID、prepare/claim/send 顺序、本地 start_intent、持久 receipt、reconcile、终态 CAS 与迟到证据记录；适配现有 Gateway 资源与临时 worker 监督策略。

验收：使用带持久调用计数或外部可观测计数的非 AI handler，证明各崩溃切点不会恢复重执行；只读证据查询与重复 receipt 传输幂等；相同 ID 不同 digest 拒绝；写日志失败零启动；最终结果写失败不能宣称 durable success。默认本地执行也经过 Gateway 和日志。

停止分类须回归 `e9bd6b4` 的契约：首个 deadline/cancel 触发原因拥有 provenance；相符的终止才是 execution-origin `deadline/cancelled + worker_stopped`；正常返回保持 success，无关崩溃保持 worker_lost。持久日志/receipt 保存停止原因与终止观察，覆盖竞争触发、kill escalation、终态保存前/后崩溃、重传和迟到消息。仅有停止请求或旧 start_intent 不能在重启后生成“已停”的终态；Coordinator 的 termination_unconfirmed/cancel_unconfirmed 仍保持不确定性。

保留 owner 失效时冻结/清理、Directory 过期、容量释放、不确定性、不自动替换环境及既有 submit 验证。确认持久提交延迟不会在同步 GenServer 回调里引入无限等待；采用有界提交协调、队列及超时，超时须有稳定提交 ID 可核查。

### C. Agent 历史、检查点与恢复

依赖 B。产物：持久 Agent definition/secret refs、消息历史记录、完整模型 request/reply、原子 Tool batch、消费去重、自足检查点、继续位置、恢复说明、paused restore、显式 continue。不新建 Task 状态机或事件重放引擎。

验收：使用确定的 fake provider/Tool，多工具并发且反序完成仍按原序进入上下文；完整回复保存后不再次请求模型；消费前/后崩溃仍只消费一次；每个继续位置都验证恢复。缺少 secret/profile/environment、未知 schema、artifact 损坏进入 blocked，零替代环境/节点派发。两个恢复请求及旧代写入只产生一个活跃实例。

接入 `complete/3`、`complete_tool/3`、`batch/2` 等业务转换，而不是订阅 `publish` / `publish_activity` 后落库。注入提交失败应证明：未提交输入不确认、Tool 批次不部分派发、消费未提交不启动下一步、Coordinator 终态未提交不通知 sink。保留既有有界 display/subscription 行为，但它们不参与提交协议。

补充用例：构造超过 display 最近条数/字段预算的合法上下文，及 display 全部省略的快照，验证历史/导出/fork 仍获得完整已接受内容；恢复后注解重新生成、不含旧 reference/订阅，展示不能作为模型输入。测试 Tool 的 uncertain 和未确认停止在持久模式下成为 blocker，零自动下一轮模型请求/替代 Tool 派发，显式解决后才推进。

既有模型凭据传输仍受原限制；secret ref 解析值不得进入普通持久投影/历史/导出/错误。对临时凭据 API 给出明确迁移及临时模式兼容，不静默持久化旧输入。

### D. 历史查询与导出

依赖 C。产物：持久 locator 查询、Agent/as-of 视图、fork 来源、执行证据审阅、keyset 分页、固定高水位、版本化导出包及只读验证器。首版不自动 GC，不增加保留 pin/租约或导出调度器。

验收：Agent 未运行时完整读取；导出期间同时产生新事件，导出范围仍不漂移；继承上下文与本 Agent 执行可区分，来源路径未包含的审计轨迹和跨权威缺失关系明确；受限内存；脱敏标记；没有凭据和活对象。验证 JSONL 可逐条读取并对 artifact digest 校验。检验同一历史可支持故障复盘、用量/本地耗时统计、源/新 Agent 路径比较和离线评测样本；不把 sampled span 当作恢复依据。

### E. 回撤与恢复决定

依赖 C、D。产物：安全检查点判定、源 Agent 冻结退役、fork 原子创建新 Agent、上下文复制与来源标记、显式风险接受、人工证据 resolution、新 Operation 的 retry_of。不创建 branches 表或 active-branch 切换接口。

验收：fork 返回新的稳定 Agent locator，旧 Ref/别名不重定向；新 Agent 从 paused/await_input 开始，可不读取父 Agent 独立加载。复制上下文保留完整 Tool-call 配对和配置；大 artifact 可共享。源 Operation/Execution/证据、pending 工作、命令去重、消费集合、取消状态和 provider session 不复制；继承 usage 不重复计费。回撤前后原历史字节不变，原 Agent 的迟到结果不污染新 Agent；未确认可能改变共享环境的旧执行已停时默认禁止新 Agent 继续；显式风险接受留事件；原环境改变仍存在。复制事务失败无部分新 Agent，同 command 重试返回同 locator，超限不截断。先 uncertain 后 success 不覆盖已接受 Result，只通过显式采纳推进暂停上下文。

### F. 发布与运维闭环

依赖 A–E。产物：CLI/daemon 显式存储配置、独立迁移命令、备份恢复说明、journal 水位/保留指标、双数据库 CI、复制 release 的持久卷 smoke 场景。

验收：authority-only、executor-only、interaction-only 及全部组合角色不误启 Repo；interaction-only 不要求数据库；executor-only 不启动 Agent。数据库失联/磁盘满时 durable 准入状态和错误诚实，不改变现有 Node 注册 ready 的语义；在 Repo/Node/Gateway 仍存活且已注册时注入写失败，证明 authority 新输入/派发或 executor 新启动被相应阻止，无内存降级；observations 的旧报告、超时或 partial/complete 不决定是否可执行；恢复备份后默认暂停核对；备份包可恢复到隔离测试部署。SQLite 嵌入引擎版本明确，禁止网络文件系统 WAL。

## 3. 故障注入方法

每个测试使用明确切点 barrier：事务前/后、send claim 前/后、admit 前/后、start_intent 后、handler 外部改变后、receipt 提交后、authority accept 后、context consume 后、fork 新 Agent/上下文事务提交前/后。

分别终止业务进程、Gateway、authority VM 和 executor VM，而不只测试异常返回。持久化测试用磁盘数据库，不能用内存 SQLite 冒充进程/VM 重启证据。断网后使用独立控制通道查看远端 handler 计数，不能把本地 DOWN 当作远端已停。

断电/fsync 的物理耐久性与 kill VM 测试分开记录；测试通过只证明实际覆盖的故障模型。不要声称仅凭同主机 peer suite 证明跨物理主机部署或电源故障保障。

## 4. 负载、容量与观测

实现任务必须给出并验证具体默认值：事务/查询超时、SQLite busy 等待、提交队列深度、每次事务/事件/检查点字节、artifact 大小与总配额、分页条数、证据批量及重传退避、fork 上下文复制大小、导出并发。

这些值沿用当前 Operation/Result 等协议上限作为输入约束；不要通过改大 wire limit 绕过历史容量问题。至少以多 Agent 并发、多 Tool 结果、慢磁盘、慢导出和长历史验证有界性，再确定产品吞吐目标。没有测量前不承诺固定 QPS。

指标：事务延迟/失败/结果未知、busy/conflict、队列深度、WAL 大小与 checkpoint 阻塞、未确认 receipts 与最老年龄、unknown execution、恢复 blocked 原因、artifact 完整性、导出失败、按角色区分的 durable 准入状态/安全原因（不混同 Node 注册 ready）；日志只含 IDs 和安全原因。

## 5. 实现期验证及暂停点

实际新增依赖/代码后，按 [Backend Quality Guidelines](../../.trellis/spec/backend/quality-guidelines.md) 运行格式、warning-fatal compile、针对性与完整 ExUnit、显式 named distributed suite、静态检查及 release 验证。双库迁移和存储契约均不可跳过。未来命令示例不作为本轮测试结果。

必须暂停扩大范围的条件：无法定义某个继续位置；业务事实与事件无法同库原子写入；需要自动重执行才能使测试通过；凭据无法与持久描述分离；回撤依赖假定远端已停；SQLite/PostgreSQL 行为产生不同业务结果。先修订设计并评审，不以新中间件、自动切主或伪造 certainty 掩盖问题。

每阶段可通过保持原临时入口、禁用新的 durable 创建来停止上线。已写入 durable 数据不可用旧内存实现悄悄接管；数据库迁移回滚以备份/兼容读取策略处理，不直接 DROP 历史表。

## 6. 复杂度验收

只新增历史记录、检查点两项 durable 原语；fork/回撤是复制上下文并创建新 Agent 的操作，不是独立 Branch 实体。Operation/Execution/Result 不改为 Task/Workflow。首版权威存储八张业务表（迁移元数据除外），executor 一张 attempt 日志表；不含 branches、branch_id、active_branch_id 或 parent_cut_seq。表数是审查基线，确需增加须说明无法合并的约束，不把表数当形式指标牺牲正确性。

不增加 Display/Observation 表、第二份 transcript 或存储健康调度器。Display 注解、activities、订阅和旧 Ref 不进检查点；可保存的展示标签只作为已校验 metadata，不代替真实配置和 secret refs。

每阶段审查：能否复用 Ecto.Multi/现有 Agent 状态机/现有 Gateway；是否增加了一个没有第二个真实用途的 behaviour；是否把字段升级成实体；是否重复保存 message 与 event；恢复是否需要运行旧业务代码；导出是否被迫依赖新后台服务；加载 fork 后的 Agent 是否需要递归祖先或切换 active branch。出现这些情况先简化再继续。

[研究记录](./research/durable-agent-mechanisms.md)中的 replay-safe、通用 Document、Task scheduler、Temporal workflow replay 均不进入首版。后续若需要安全自动重执行或复杂 durable workflow，应作为独立需求讨论。

## 7. 本轮文档验证范围

本次文档修补只验证本地链接/源路径、Markdown 结构与空白、术语及主设计/本计划的一致性。没有安装 Ecto，没有更改应用、配置或依赖，没有运行数据库测试；未来实施阶段以各自验收记录为准。

修补所依据的兼容性核对基线为 `a078aa3`（主设计第 2 节）。前序核对运行了以下现有内存实现测试：

- `apps/beamlet_runtime/test/beamlet/deadline_classification_test.exs`
- `apps/beamlet_runtime/test/beamlet/observation_test.exs`
- `apps/beamlet_agent/test/beamlet/agent/display_projection_test.exs`
- `apps/beamlet_agent/test/beamlet/agent/display_test.exs`
- `apps/beamlet_node/test/beamlet/observation_test.exs`

结果为 Runtime 13、Agent 15、Node 8，共 36 项通过；distributed 标签默认排除。这只是现有观察/停止分类/展示行为的回归证据，不证明任何未来持久化、数据库事务、跨节点恢复或物理耐久性保证；本次仅文档改动未重跑这些应用测试。
