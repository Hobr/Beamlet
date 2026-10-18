# 持久化设计原文快照：导出、fork、数据库与故障（8–13）

用途：规划上下文分片，避免 Trellis 单文件 32768 字节注入上限截断主设计；不是第二份权威设计。节选只调整相对链接以适配本目录，不改变原契约。

来源：[主设计](../../../../docs/architecture/agent-operation-persistence.md) 在 2026-10-18 文档修补后的工作树内容，代码兼容性基线 a078aa3。以下为对应章节原文；开工前须对照当前主设计检查差异。主设计更新时应重新生成受影响分片，不以旧快照覆盖新契约。全部章节的整体关系见[父设计](../design.md)与[交付计划](../../../../docs/architecture/persistence-delivery.md)。

---

## 8. 历史审阅与轨迹导出

历史查询以持久 locator、turn、operation、事件 cursor 为入口，不依赖活跃 Agent/Coordinator，也不返回活跃 PID。至少支持：轮次列表、有效上下文、fork 来源、每步模型输入输出、Tool 请求与结果、执行证据、取消/不确定性、恢复/重绑定/回撤决定、委派因果关系。

区分三种视图：某时刻保存的事实、某 Agent 的有效上下文、当前运行观察。提供 `as_of_seq`、继承消息来源和 artifact 完整性状态，避免把源 Agent 的迟到结果显示为新 Agent 的当前上下文。

默认导出格式为版本化 manifest + JSONL events + checkpoints + artifacts。Operation 的历史描述、执行证据与终态来自指定高水位内的不可变事件；messages 是 events 的消息视图，不再导出一套独立权威记录。manifest 包含 export version、authority/Agent IDs、fork 来源、范围、各 scope 的固定高水位、内容 digest、缺失项、脱敏策略及 `history_complete`。每条事件有 scope/seq、causation ID 和原始 recorded_at；不伪造跨 Agent 全局顺序。

大数据先固定高水位，再用短事务 keyset 分页读取不可变记录；不能混入当前可变状态。首版不自动删除历史/artifact，因此无需导出 pin、租期、GC 协调或导出调度服务；显式删除数据集须由运维在停止导出后执行。未来确需在线删除再设计保留协调。避免长事务拖住 SQLite WAL checkpoint。

默认导出只含所选 Agent 及其已经复制的初始上下文；不追溯加载祖先来拼接历史。原 Agent 的完整审计事实不随 fork 复制，来源仅为 provenance：新 Agent 的上下文/恢复可自足，但不能声称包含来源路径的完整执行轨迹。跨 Agent/权威的原始执行或委派轨迹以 external reference/未包含状态表示，另行显式查询。导出不执行代码，不自动包含 executor 整库或 secret refs 的解析值。导入（将包变成可执行 Agent）延期；读取/验证导出包不等于导入授权。

轨迹反映已观察行为与规范化输入输出，可重建上下文，但不能保证重新调用模型得到相同内容。脱敏导出允许丢失内容并标记，不再承诺可恢复。

### 8.1 轨迹的具体用途

| 用途 | 必需事实 | 首版处理 |
| --- | --- | --- |
| 恢复与继续 | checkpoint、请求身份、已接受结果及消费状态 | 核心能力；不依赖可丢失 span/token |
| 故障复盘与审阅 | 实际模型输入输出、Tool 参数/结果、因果、执行证据和用户决定 | 核心查询；区分当时事实与后来证据 |
| 回撤与方案比较 | 复制的上下文、来源检查点、配置版本 | 保留原 Agent；比较两条独立路径 |
| 成本与性能分析 | provider/model、usage、已知费用、各节点本地 duration | 查询/导出字段；费用未知标 null，跨机时钟不直接相减 |
| 评测与回归样本 | 输入、实际配置、预期结果/人工标签、Tool 轨迹 | 允许离线导出，执行评测需独立 fake/sandbox，不重放真实副作用 |
| 上下文策略改进 | 原 messages、实际发送的 context manifest、压缩/重置来源 | 可检验遗漏与 token 开销；压缩不删除原事实 |

恢复记录与可观测 tracing 可以使用相同稳定 ID，但 span 不是恢复事实源。当前不建 span 存储、评分器、训练平台或采集私有思维链。评分、人工标签和训练集转换可在导出后完成，不增加核心调度原语。后续接 OpenTelemetry 等应是可丢失的派生投影，失效不能阻塞结果持久提交。

## 9. 回撤：从检查点复制上下文并创建新 Agent

回撤通过 `fork(checkpoint) → new Agent` 实现。不在同一个 Agent 内切换 active branch，不设 branches 表、branch_id 或祖先前缀解析。原 Agent 的消息、Operation、Result 与事件不删除、不修改；新 Agent 获得独立 ID、历史序号和 head checkpoint。旧 locator/Ref 始终指向原 Agent，调用方须显式使用返回的新 locator，不能偷偷重定向别名。

只从 `safe_to_fork=true` 的检查点复制：完整消息边界，Tool-call/result 配对完备，无未消费模型回复/Tool 结果，无在该检查点之前尚待决的 Operation、委派或 peer 请求。任意 token/任意事件点回撤延期。原 Agent 在此检查点之后可能仍有活跃工作，继续前仍需核对共享环境风险。

复制范围与身份规则：

| 内容 | fork 行为 |
| --- | --- |
| 有效用户/助手/Tool 消息、系统配置、Tool schema、压缩摘要 | 物化为新 Agent 的继承上下文记录，分配新记录 ID，保留来源标记 |
| 不可变图片、大输出及其他 artifact | 允许共享同一权威库的内容引用；引用同事务验证，加载不需要读取父 Agent |
| Operation / Execution / evidence | 不复制成新执行实体；旧 Tool 返回值只是继承的上下文，原证据仍归原 Agent |
| command 去重、pending/join/consumption、取消与委派/peer 状态 | 不继承运行控制状态；新 Agent 从空的工作集合开始 |
| PID、订阅、timer、provider session | 不继承；需要时建立新运行身份 |

在 `agents` 上保存 `forked_from_agent_id`、`forked_from_checkpoint_id`，继承消息可保存 `source_agent_id` / `source_event_id`。这些是来源信息，不构成加载依赖。Tool-call 配对标识在新上下文内保持一致；后续新调用使用新的身份，不与继承消息混淆。新 Agent 的历史明确区分“继承的观察”和“本 Agent 实际执行”，不能把原执行伪装成新 Agent 的工作，也不能将继承的 usage 算作新费用。

流程：

1. 回撤原 Agent 时先冻结其当前轮次，提交禁止新派发，等待本地派发辅助进程退役，并增加 generation 拒绝旧写入。单纯复制历史用于审阅不要求停止原 Agent，但也不授予新 Agent 执行权限。
2. 对原 Agent 后续已派发的工作请求取消/查询。确认本地冻结不等于远端停止；若不能确认可能改变共享环境的旧工作已停，默认禁止新 Agent 继续执行。
3. 以源 Agent 的 expected_version 和不可变 checkpoint ID 校验，在一个权威事务内创建新 Agent、复制完整有效上下文、保存新的初始 checkpoint、fork 来源事件及 command 响应。新旧记录的映射在提交时确定；事务失败不留下部分可恢复的新 Agent，同 command 重试返回相同新 locator。首版 fork 留在同一权威，不增加跨库复制协议。
4. 新 Agent 保持 paused，初始继续位置为 `await_input`，不复制源检查点的执行继续位置。返回新 locator 和复制内容摘要；用户显式输入后才发起新 Operation。恢复新 Agent 只读取自身上下文和共享 artifact，无需遍历父链。
5. 继续前重新核对环境和未决风险；必要的风险接受通过显式命令留痕。provider 会话重新建立。原 Agent 的迟到证据只更新原历史，不自动追加到新 Agent；需要采纳时是新的显式上下文输入。

复制成本是存储与事务大小的明确取舍。设置复制上下文/事务的大小上限，超限明确拒绝，不静默截断，不先引入 staging 作业框架。未来若确需同一 Agent 内切换大量路径，或测量证明复制成本不可接受，再单独讨论 Branch 实体或共享前缀。

即使确认旧 worker 已停，已经写入的文件、发送的请求、模型费用也不会撤销。需要文件系统快照/补偿操作属于 provider 或未来功能；fork 不能被描述为外部环境 rollback。

## 10. 公共接口收敛

沿用已有 Agent 生命周期/输入和 Runtime submit/status/cancel；持久化是显式启动配置及 locator 支持，不再另造一套 durable 工作接口。具体参数在实现任务中确定。

| Interface | 语义 |
| --- | --- |
| 现有 `Agent.start` / `input` | 持久模式先提交定义/输入，以 command_id 幂等；凭据由引用解析 |
| `Agent.restore(locator, expected_version, command_id)` | 创建新的暂停实例，返回恢复说明；不重新执行 |
| `Agent.continue(ref, expected_version, decisions, command_id)` | 单一恢复决定入口；保存采纳/放弃/新工作决定后推进，内部核对 Operation 版本 |
| `Agent.history(locator, filters, cursor)` | 查询检查点、消息视图、fork 来源和执行证据，不启动业务进程 |
| `Agent.fork(locator, checkpoint_id, expected_version, command_id)` | 原子创建独立的新 Agent 并返回新 locator；复制上下文、来源及执行限制见第 9 节 |
| `Agent.export(locator, scope, policy)` | 有界流式导出固定范围，返回 manifest；不引入导出任务系统 |
| 现有 `Runtime.status` 的持久 locator 入口 | 返回 Operation 已接受 Result 和相关证据；协调器退出后仍可读 |

证据核对与记录解决决定是 Runtime/Agent 的私有协作函数，不设独立 Reconciler、Resolver 服务。Storage 是内部实现，不提供公共 `commit(bundle)` 协议。Ecto.Multi 已满足组合事务需求。

统一错误须区分 `storage_unavailable`、`storage_outcome_unknown`、`conflict`、`stale_generation`、`schema_unsupported`、`dependency_missing`、`evidence_unavailable`、`unsafe_checkpoint`、`unresolved_execution`、`artifact_missing` 和普通业务 error。提交结果未知时按 command_id/稳定事件 ID 重读确认；数据库可达前不重发外部工作。Storage 内部只允许对纯数据库事务进行有界竞争重试，不重复外部副作用。

## 11. SQLite / PostgreSQL 实施约束

| 方面 | SQLite 默认 | PostgreSQL 可选 |
| --- | --- | --- |
| Ecto | ecto_sqlite3，独立 authority / journal 文件 | Ecto.Adapters.Postgres + postgrex，authority 专属 schema/库 |
| 持久化设置 | 本机持久卷、WAL、synchronous=FULL、foreign_keys=ON、有界 busy_timeout；启动核查实际 PRAGMA | 普通持久表；保持 fsync/同步提交，不使用 unlogged 表替代事实 |
| 写并发 | 单 writer，短事务；必要时 authority 内有界提交队列；不对 token 每次写库 | 行版本 CAS + 唯一约束，连接池有界 |
| 事务 | Ecto.Multi；实现时验证 adapter immediate mode 的使用 | Ecto.Multi；Read Committed + 单行 CAS，不依赖先 SELECT 后无条件 UPDATE |
| 类型 | UUID 逻辑上是规范字符串；JSON/map 按 codec 验证，BLOB 保存 artifact | 相同外部契约；可用 native JSONB/bytea 的 adapter 映射，不暴露差异 |
| 查询 | 显式 B-tree 索引；有界 keyset 分页 | 相同查询语义，初版不要求 JSONB 查询/GIN/notify |
| 测试 | 独立文件；写库 sandbox 用例不能假设 async 安全 | 相同契约套件 + 实际并发测试 |

可移植迁移只依赖主外键、非空、唯一约束、索引和版本列。enum/版本范围等不能依赖某一 adapter 默认实现；通过 codec/changeset 与针对两库验证过的约束共同保证。不可依赖 PostgreSQL advisory lock、SKIP LOCKED、部分索引或 LISTEN/NOTIFY 才能保证正确性。查询更新以受影响行数和唯一冲突作为事实，不依赖所有 adapter 都支持相同 RETURNING。

权威和 executor journal 各有 migration 目录/版本；部署显式迁移成功并核对存储状态后才开放相应持久准入。迁移是单一运维动作，不由每个 Agent 启动。升级采用 expand → 回填 → 校验 → 切换，破坏性删除另行安排；数据版本较新时旧代码拒绝写入。事件保留原 schema version，读取时用普通版本分支转换；不另造 upcaster 框架，不能通过升级重新执行旧 handler。

当前 Node services `ready` 仅表示所需本地进程已注册，Runtime report readiness 也不提供磁盘提交保证。保留这些现有语义；持久准入须在实际 authority 事务及 Gateway 日志路径中强制检查，不能依赖 observation 快照。Repo 进程存在不等于数据库可写，启动检查通过也不能代替逐次提交。若对外展示存储状态，使用单独明确标注的 durable 准入状态及安全原因；该派生状态不授予执行权限，也不是新的持久实体。

数据库忙/磁盘满/写失败：停止受影响角色的新持久输入接受和新派发，关闭相应 durable 准入。已在执行的外部工作未必能停止；尽力取消并保留 unknown。只读可行时仍提供历史。数据库恢复后先重读确认提交、reconcile，再允许显式继续。

SQLite 备份必须使用一致性备份能力或停写并正确处理 WAL，不直接复制正在写入的单个 `.db`。PostgreSQL 使用一致性备份流程。恢复旧备份可能丢失已提交 dispatch/去重记录：必须标记 `restored_backup` 并暂停业务，执行人工/证据核对，不能当成从未派发直接继续。

初版 artifact 放数据库内以保持原子性。之后若改对象存储，必须另设 staging/commit/GC 协议与缺失语义，不让“上传成功但引用未提交”变成隐含保证。默认不自动清理业务事实；progress、已确认 executor receipts 可按策略清理。未确认 receipts 不静默删除，达到磁盘/配额水位则停止新 durable 准入。权威 ACK 后仍保留 journal_attempts 的去重身份；首版不删除 attempt 记录，也不增加 epoch/回收协议。日志丢失或从旧备份恢复后执行节点默认暂停准入，先完成运维隔离和核对，不能把缺失的旧 attempt 当新工作。

## 12. 故障矩阵与不变量

| 崩溃/故障位置 | 持久证据 | 恢复结果 |
| --- | --- | --- |
| 输入事务提交前 | 无 command | 未接受；重试 command 不产生旧工作 |
| 输入提交后响应丢失 | command + turn | 重读同响应，不重复生成 |
| prepared 后、send_claimed 前 | 未发送 intent | 暂停，显式继续可首次派发 |
| send_claimed 后发送前/后 | 无法区分 | 查询；未找到也不自动重发 |
| executor start_intent 后启动前/执行中 | 可能执行 | unknown；不补跑 |
| 外部改变后、本地终态提交前 | start_intent | unknown；不能宣称无副作用 |
| 本地终态提交后、上报前 | 完整 receipt | 查询/重传证据，权威接受一次 |
| 权威终态提交后、Agent 消费前 | accepted_result | 纯数据消费一次，不重执行 |
| 消费事务后、下一步前 | 消费键 + continuation | 从新位置继续，不重复 Tool message |
| 先 accepted uncertain、后 receipt success | 两种观察均保留 | 显式 resolution，不能覆盖旧终态 |
| 取消/回撤中收到迟到结果 | 原 agent/turn 身份 | 只补原历史，不推进新 Agent |
| 首个 deadline/cancel 后收到竞争触发或正常返回 | 停止原因、终止观察及 receipt | 保留因果分类；正常返回不被请求改写，保存前崩溃保持 unknown |
| 展示截断/全部省略或 observation 过期 | 完整历史和检查点独立存在 | 不影响恢复/fork，不以投影缺失推断业务未发生 |
| authority DB 不可写但 Repo/Node 仍已注册 | 本地日志或未决证据 | 禁新持久输入/派发；不自动内存降级，注册 ready 不授予准入 |
| executor 日志丢失/旧备份恢复 | 证据不完整 | 保持 unknown，不能以 not_found 证明未执行 |
| 两个恢复请求/旧实例迟到写 | version + generation | 单实例激活，旧写拒绝；冻结时仍须退役旧本地发送者 |

必须一直成立：已接受输入可找回；发送前有已提交的 dispatch claim；handler 启动前有本地 start_intent；对外 durable completion 前有持久终态；每 Operation 接受一个 Result；每 Agent 消费一次；旧 Ref 不复活；回撤不删除原历史；恢复不自动重执行；所有查询与缓存都有大小和时间上限。

## 13. 设计取舍与一手依据

关键取舍：

- 选择事务状态 + 事件 + 检查点，而非纯快照或全面 event sourcing：同时满足审阅与恢复，又不把旧 handler 永久当作事件解释器。
- 默认执行日志值得增加第二份数据库：它保留丢失回执后的完成证据，但不升级为第二个业务权威。
- 不自动重发 dispatch：牺牲一部分无害情况下的自动继续能力，保留对真实副作用的诚实语义。
- 回撤复制安全检查点的有效上下文并创建新 Agent：原历史保真，新路径独立加载，不引入父前缀解析或同 Agent 内的分支切换。
- 首版 artifact 在库内：优先获得可验证的事务完整性，再按真实容量需求提取存储机制。

先 uncertain 后 success 不覆盖已接受 Result。进一步的机制调研、可借鉴点和不采纳的抽象见[研究记录](../../../../docs/architecture/research/durable-agent-mechanisms.md)。

文档核对依据（在线文档版本可能演进；实现时必须锁定依赖并重新验证）：

1. [Ecto.Multi](https://hexdocs.pm/ecto/Ecto.Multi.html)：一组 Repo 操作进入单数据库事务，操作失败回滚；不覆盖网络副作用。
2. [Ecto SQLite adapter](https://hexdocs.pm/ecto_sqlite3/Ecto.Adapters.SQLite3.html)：WAL、synchronous、busy_timeout、transaction mode 配置及 SQL Sandbox 并发限制。其 synchronous 默认 NORMAL，不能把 adapter 默认值直接当作本提案 FULL 的承诺。
3. [SQLite WAL](https://www.sqlite.org/wal.html)：同一时刻单 writer；WAL 需要同主机；FULL 在每次事务提交同步 WAL；长读事务影响 checkpoint。上线前核对实际嵌入 SQLite 版本与官方已知缺陷，不以 Elixir adapter 版本代替引擎版本。
4. [PostgreSQL isolation](https://www.postgresql.org/docs/current/transaction-iso.html)：Read Committed 下更新会在竞争后重新检查 WHERE；普通先读后写不提供跨行业务不变量。版本条件、唯一约束和共同事务不可省略。

以上是设计依据，不是当前仓库或目标硬件上的耐久性测试结果。后续实现验收见配套计划。
