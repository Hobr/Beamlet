# 持久数据契约与存储基础设计

状态：in_progress。用户于 2026-10-18 批准 A 阶段实施，包括添加已评审依赖与准备隔离数据库测试设施；B–F 未获开工授权。当前分支 feat/durable-storage。

## 设计依据

- [主设计](../../../docs/architecture/agent-operation-persistence.md)
- [实施与验收计划](../../../docs/architecture/persistence-delivery.md)
- [术语](../../../GLOSSARY.md)

以上文档是契约来源；本文只收敛本任务范围，不另建相互竞争的设计。代码兼容性核对基线为 `a078aa3`，开工前重新核对后续变化。

## 归属与方案

主设计第 3–5、11 节及交付计划 A。新增 beamlet_storage，具体 AgentRecords/OperationRecords/ExecutorJournal 函数封装 Ecto.Multi，不建通用 Storage behaviour/bundle DSL。首版权威八表为 agents、checkpoints、events、operations、executions、execution_evidence、commands、artifacts；executor 仅 journal_attempts。显式选择 SQLiteAuthorityRepo 或 PostgresAuthorityRepo，ExecutorJournalRepo 独立。迁移实现全量契约，后续阶段复用，不按每个领域名词加表。

## 本阶段的明确范围

A 新建 Storage 应用、authority/journal schemas 与迁移、严格 codec、具体存储事务及真实数据库测试。迁移覆盖主设计八张权威表及一张 journal 表；不新增领域实体。Runtime/Agent 的业务状态机、Node 的存储选项、CLI/daemon 运维入口分别留给 B/C/F，A 不以预留 stub 或新框架假装它们已实现。

新应用依赖放在自己的 mix.exs；同步根 mix.exs 的 backend_apps 白名单，使后端构建能够编译/测试 Storage。无 Application callback 自动启动 Repo。Repo 由嵌入 supervisor 或测试显式启动：同 VM 只选一个 authority adapter，executor journal 独立；启动不自动迁移。A 不修改现有临时 Runtime/Agent 行为，也不先改变 Node 的配置白名单。

## 候选依赖与启动配置

建议直接版本为 Ecto 3.14.0、ecto_sql 3.14.0、ecto_sqlite3 0.25.0、postgrex 0.22.4，Jason 保持当前 1.4.5。它们的声明约束可相交，但尚未执行依赖求解或编译；开工后先精确固定直接版本并验证 OTP 29 / Elixir 1.20 和锁文件，不用 override 掩盖冲突。[核对证据](./research/planning-evidence.md)记录官方来源及限制。

显式配置选择 SQLiteAuthorityRepo 或 PostgresAuthorityRepo，ExecutorJournalRepo 使用 SQLite；配置只在进程启动时使用，数据库 URL/密码不进入业务记录或日志。数据库路径为受信任绝对路径，authority/journal 文件不得相同。迁移前检查目录/配置与已存在的数据集身份，不能因为缺失数据库就静默新建并当作旧数据集恢复；首次初始化必须明确区分于打开已有数据集。主设计的数据集身份、备份标记和 migration version 是启动核查的一部分，不增加业务实体。

SQLite 起始配置：WAL、synchronous=FULL、foreign_keys=ON、busy_timeout=2000ms、pool_size=1；写事务显式 immediate，普通只读查询不获取 immediate 写锁。PostgreSQL 起始 pool_size=4、使用普通持久表与同步提交。所有实际连接都核查配置，不能只检查第一条连接；这些是保守起点，不是吞吐承诺。SQLite 并发测试必须包含独立连接/Repo 或进程，不能只用单连接串行测试宣称 CAS 竞争已覆盖。

## Interface 与交接

只提供有限的具体事务，不暴露任意 Repo/SQL 给 UI，不提供通用 commit(bundle)。以下是职责合同，具体参数使用命名 map/struct 并在测试中锁定，不为每个字段另造命令实体：

| 私有协作入口 | 原子边界 |
| --- | --- |
| AgentRecords.create_agent / accept_input | Agent/定义或输入、command、历史序号/事件及初始或下一 checkpoint 一起提交 |
| AgentRecords.consume_result | 校验 owner Agent/turn 与 accepted Result，在消费键唯一约束及 Agent CAS 下写有序上下文和 checkpoint |
| OperationRecords.prepare | 写 immutable Operation、唯一 attempt、prepared 状态和相应历史；不做目标选择或发送 |
| OperationRecords.claim_dispatch | expected_version/状态 CAS 为 send_claimed；只返回已提交记录，不发送 admit |
| OperationRecords.record_evidence / accept_result | receipt 身份/digest 去重与冲突记录；Result 接受只允许 NULL → 已接受，不覆盖旧值 |
| ExecutorJournal.claim_start | authority/attempt 唯一身份及描述 digest；新纪录先写 start_intent，重复调用只返回既有状态 |
| ExecutorJournal.record_stop / record_terminal / acknowledge | 首个已记录停止原因不覆盖，终态/receipt 原子保存，ACK 只记录持久证据接收；不执行取消或启动 worker |
| 对应模块的 fetch / history_page | 只读稳定 ID、有限 keyset cursor；不恢复进程，不推断执行未发生 |

输入为明确字段的数据与预期版本；数据字段按主设计第 4–5 节逐项声明/校验，不直接接收现有 Operation/Result/Ref 的 struct dump。Runtime/Agent 负责业务决策，Storage 必须独立验证身份、合法数据、唯一性、版本和引用完整性；不能信任上层“已经校验”而绕过存储约束。

fork、restore/continue 的进程控制和导出序列化不在 A；E 的同事务复制函数在 E 增加，不先建通用批次事务框架。B/C 可基于本阶段具体函数扩展必要字段，但改动交接契约时先同步阶段设计。

## 数据与事务规则

- JSON 仅字符串键、合法 UTF-8、布尔/null、有限数值、数组与 plain map；枚举按 schema 白名单从 atom 显式转字符串，不对任意 atom/tuple/struct 做通用 stringify。基础 codec 不接受整个 Operation/Result 的活结构。
- Operation 的持久描述显式排除 credentials，只保存配置/secret 引用；allowed_nodes 的 node atom 经受信任配置转换为字符串引用，不在加载时 String.to_atom。Result 的已知状态/来源/原因有显式映射，无法安全持久化的值明确拒绝，不能 inspect 后假装可恢复。
- 固定 schema 不含密钥值字段，拒绝未知字段及结构化凭据输入。codec 不能识别任意文本里的秘密，不能承诺自动秘密扫描；文本政策、数据库/备份权限及提供者不得输出凭据仍是独立约束。
- ID 为规范字符串，时间统一 UTC 审计值；本 VM monotonic timestamp、timer、PID/reference 不进入数据。digest 使用稳定的键排序 JSON 编码及 SHA-256，明确数值类型/字符串不做隐式归一化；原始内容同时保留，不以 digest 代替可恢复数据。
- Agent/Operation 版本及 history_seq 由同事务 CAS 推进，唯一约束作为并发事实。command 保存请求 digest 和提交响应；相同身份/参数重读原响应，不同参数 conflict。receipt 相同身份不同 digest 作为冲突证据，不能覆盖原内容。
- artifact 内容/引用同库提交并验证 digest；八表引用、不可空字段、版本/枚举及允许范围由 codec/changeset 与可移植约束共同保证，两 adapter 测同一结果。不依赖 PostgreSQL 部分索引、advisory lock 或特有 RETURNING。
- 事务内部不进行网络发送/模型/Tool/文件系统副作用。仅数据库竞争可有界重试；A 默认不自动重试写事务，调用方以原 command/稳定身份核对。提交结果未知须返回 storage_outcome_unknown，不能转成“未发生”。

返回普通数据：成功包含已提交 ID/版本及保存的 command 响应；错误至少区分 invalid_data、limit、conflict、stale_generation、schema_unsupported、artifact_missing、storage_unavailable、storage_outcome_unknown。底层 SQL/连接错误、配置和秘密不能直接穿透到公共错误或持久事件。

## 起始资源上限

以下是待真实负载验证的 A 默认值，超过上限明确拒绝，不静默截断；不能通过放宽 wire limits 绕过。JSON 字节指规范化编码后的 UTF-8 字节，与既有 Erlang wire 大小分别验证。

| 项目 | 起始值 |
| --- | --- |
| codec 嵌套深度 / 总节点数 | 32 层 / 100000 节点，遍历提前截止，含键与标量 |
| 单持久 Operation 描述 / command 请求或响应 | 各 1 MiB |
| 单历史事件 / checkpoint 描述 / Result 数据 | 各 4 MiB；完整上下文原有 128 条/1 MiB 契约仍适用 |
| 单 artifact / 单事务新增逻辑数据总量 | 16 MiB / 32 MiB；是逻辑预算，不是数据库/WAL 物理空间上界 |
| history_page 默认 / 最大条数 | 100 / 500；另限单页 4 MiB，超大单条走 artifact/明确错误，不无限拉取 |
| Repo 查询/事务预算 | 5000ms；SQLite busy 等待 2000ms，调用方总预算必须覆盖排队/执行并有界 |

数据库调用 timeout 不是取消外部事实或回滚成功的证明；一旦提交结果可能未知，按稳定身份核对。双库必须验证实际 timeout/连接错误路径，不声称这些配置提供硬实时保证。持久卷总配额、journal 高水位和产品并发目标由 B/F 结合测量收敛；A 不自动 GC 或加入容量调度服务。

## 依赖与兼容

先决：无上游实现任务；本子任务已获用户评审批准。

遵循[父设计](../10-18-agent-operation-persistence/design.md)的跨阶段契约、单权威部署与回退限制。具体源码位置开工前重新核对；这里只记录 seam 和职责，不以基线函数签名冻结未来实现细节。现有临时模式不能被持久失败静默接管。

## 验证边界

本阶段以自身 PRD 验收及交付计划对应阶段为准；保存实际测试命令、适配器/SQLite 引擎版本、故障切点和证据路径。未执行的故障模型必须明示，不能把相邻阶段或内存测试当作本阶段证据。
