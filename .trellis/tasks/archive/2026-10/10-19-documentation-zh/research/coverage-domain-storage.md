# 领域存储中文覆盖交接

STATUS: COMPLETE

## 范围与依据

本批仅修改两个应用 lib 下36个生产文件的文档属性/注释，新增两份 README_zh.md 及本交接。不改运行表达式、签名、类型、测试、配置、依赖或历史；无提交和暂存。中文在既有英文前，不新增英文翻译。全部36文件正文完整阅读；未把隐藏模块公开。

已读子/父 PRD、design、implement、implement.jsonl 所列规范和共同清单、lanes.md、before-dev 技能、backend directory/quality/typespec/database/agent-durable/durable-references/error-handling 及 shared guides index/cross-layer guide。调用依据：两个应用 mix.exs、既存 Agent Storage README、Actions actions_contract_test/journal_test 全文、Agent Storage contract_test 全文及 dataset_test 安装段、Agent fork_test 相关断言、Runtime.Persistence 与 Agent.Durable 全文。History/export 剩余测试仅检索用例位置，不声称全文审阅或本次运行。

## 逐文件模块与 API

schema 的 changeset/t 与框架列类型仍是内部边界；nil 构造状态不代表有效持久化行。未为简单字段和委托添加重复公开说明，原 @doc false/@moduledoc false 保留。

| 源路径 | 实际模块 | API/类型及说明决策 |
| --- | --- | --- |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/codec.ex` | `Beamlet.Actions.Storage.Codec` | kind 类型及 limit/encode/decode/digest/hash/uuid?：领域预算与 foundation 规范字节分层。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/dispatch_scopes.ex` | `Beamlet.Actions.Storage.DispatchScopes` | create/rotate、事务参与者、current、validate_binding/check/reauthorize：scope→Operation 锁序，轮换栅栏与显式重授权。私有 eligible?/locked 由门面协议覆盖。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/executor_journal.ex` | `Beamlet.Actions.Storage.ExecutorJournal` | claim_start/record_stop/record_terminal/acknowledge/mark_unknown_after_restart/fetch：只登记一次、首因保留、原子终态及未知重启不能重试。私有 CAS/冲突分支由公开协议及注释覆盖。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/json.ex` | `Beamlet.Actions.Storage.JSON` | 内部 Ecto.ParameterizedType init/type/kind/cast/dump/load 与 params；保持隐藏，普通注释解释严格列边界。框架协议转交无需扩大公开文档。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/migrations/authority_v1.ex` | `Beamlet.Actions.Storage.Migrations.AuthorityV1` | 隐藏 up/down 前向迁移：中立表/FK/唯一性及适配器 DDL，中文注释解释显式安装边界；不改安装实现。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/migrations/journal_v1.ex` | `Beamlet.Actions.Storage.Migrations.JournalV1` | 隐藏 up/down 前向迁移：状态及去重索引，中文注释解释显式安装边界。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/operation_records.ex` | `Beamlet.Actions.Storage.OperationRecords` | Actions operation/attempt 类型及 prepare/prepare_in_transaction/claim_dispatch/record_evidence/accept_result/fetch；Agent operation/attempt 类型、只读 fetch 和隐藏 validate_operation/validate_attempt。隐藏标记保留；私有描述、角色和事件辅助由门面契约覆盖。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/profiles.ex` | `Beamlet.Actions.Storage.Profiles`, `Beamlet.Actions.Storage.SQLiteAuthorityRepo`, `Beamlet.Actions.Storage.PostgresAuthorityRepo`, `Beamlet.Actions.Storage.ExecutorJournalRepo` | Profiles 描述符/组件/迁移构造与同文件 Repo 模块：format3 清单，显式启动。Actions 三个 Repo 保持隐藏，Agent 两个已有公开 Repo 补中文说明，宏生成函数无新增接口。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/read.ex` | `Beamlet.Actions.Storage.Read` | 内部 read/1 保持隐藏：窄化匹配 Ecto struct_load! 严格 JSON 错误，其他异常保留原堆栈。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/record_changeset.ex` | `Beamlet.Actions.Storage.RecordChangeset` | 内部 build 与私有字段校验保持隐藏；普通注释解释未知键/同类键及列级校验与事务所有权约束的区别，不逐字段复述。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/records.ex` | `Beamlet.Actions.Storage.Records` | error/result/value/object 类型；transact、fields/uuid/optional_uuid/text/optional_text/count/digest/json/enum/get/insert/changeset_error/plain 逐项中文说明。Agent 另审 event_type/cas_agent/event_changeset/command_changeset/event_input/command_lookup。settle/plain_key 私有辅助不单独公开，plain 保留任意叶，不冒充 JSON 验证器。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/dispatch_scope.ex` | `Beamlet.Actions.Storage.Schema.DispatchScope` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/execution.ex` | `Beamlet.Actions.Storage.Schema.Execution` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/execution_evidence.ex` | `Beamlet.Actions.Storage.Schema.ExecutionEvidence` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/journal_attempt.ex` | `Beamlet.Actions.Storage.Schema.JournalAttempt` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 完整附件校验归 ExecutorJournal 原子终态协议。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/operation.ex` | `Beamlet.Actions.Storage.Schema.Operation` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/schema/operation_event.ex` | `Beamlet.Actions.Storage.Schema.OperationEvent` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_actions_storage/lib/beamlet/actions/storage/terminal_artifacts.ex` | `Beamlet.Actions.Storage.TerminalArtifacts` | container 类型与 encode/encoded_size/content：version1 容器、base64/摘要/大小、64项与16/24MiB限制；不证明 authority 存在性。私有逐项解码在公开完整性契约中解释。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/agent_records.ex` | `Beamlet.Agent.Storage.AgentRecords` | position 类型；create_agent/accept_input/prepare_operations/consume_results/checkpoint/advance/fork/restore/fetch/command_response/history_page 全覆盖。审阅私有命令重放、锁序、来源、关联和重新授权；policy 预检仍属 Agent/Core。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/codec.ex` | `Beamlet.Agent.Storage.Codec` | kind 类型及 limit/encode/decode/digest/hash/uuid?：领域预算与 foundation 规范字节分层。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/events.ex` | `Beamlet.Agent.Storage.Events` | version/agent_types/supported?/control：事件版本及 body-free 限制；私有递归不公开，不冒充完整 reducer。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/history.ex` | `Beamlet.Agent.Storage.History` | event_page/event/operation_event/checkpoint_at/checkpoint_page/turns/operations/operation/evidence 全覆盖。keyset、固定高水位、完整超预算单行、32+1 证据溢出检查；私有查询/游标工具由门面说明覆盖。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/inheritance.ex` | `Beamlet.Agent.Storage.Inheritance` | source_position/build/verify/input/operation/authorized?：原所有权、直接闭包、摘要绑定与5秒/128/1024预算。capture/covered 等私有遍历由公开约束覆盖，不递归父历史但仍须保留引用事实。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/json.ex` | `Beamlet.Agent.Storage.JSON` | 内部 Ecto.ParameterizedType init/type/kind/cast/dump/load 与 params；保持隐藏，普通注释解释严格列边界。框架协议转交无需扩大公开文档。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/migrations/agent_v1.ex` | `Beamlet.Agent.Storage.Migrations.AgentV1` | 已有公开 Agent 迁移模块及 up/down：表与只读视图，前向不可逆，DDL 保持不变。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/operation_records.ex` | `Beamlet.Agent.Storage.OperationRecords` | Actions operation/attempt 类型及 prepare/prepare_in_transaction/claim_dispatch/record_evidence/accept_result/fetch；Agent operation/attempt 类型、只读 fetch 和隐藏 validate_operation/validate_attempt。隐藏标记保留；私有描述、角色和事件辅助由门面契约覆盖。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/profiles.ex` | `Beamlet.Agent.Storage.Profiles`, `Beamlet.Agent.Storage.SQLiteAuthorityRepo`, `Beamlet.Agent.Storage.PostgresAuthorityRepo` | Profiles 描述符/组件/迁移构造与同文件 Repo 模块：format3 清单，显式启动。Actions 三个 Repo 保持隐藏，Agent 两个已有公开 Repo 补中文说明，宏生成函数无新增接口。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/read.ex` | `Beamlet.Agent.Storage.Read` | 内部 read/1 保持隐藏：窄化匹配 Ecto struct_load! 严格 JSON 错误，其他异常保留原堆栈。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/record_changeset.ex` | `Beamlet.Agent.Storage.RecordChangeset` | 内部 build 与私有字段校验保持隐藏；普通注释解释未知键/同类键及列级校验与事务所有权约束的区别，不逐字段复述。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/records.ex` | `Beamlet.Agent.Storage.Records` | error/result/value/object 类型；transact、fields/uuid/optional_uuid/text/optional_text/count/digest/json/enum/get/insert/changeset_error/plain 逐项中文说明。Agent 另审 event_type/cas_agent/event_changeset/command_changeset/event_input/command_lookup。settle/plain_key 私有辅助不单独公开，plain 保留任意叶，不冒充 JSON 验证器。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/agent.ex` | `Beamlet.Agent.Storage.Schema.Agent` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/agent_operation.ex` | `Beamlet.Agent.Storage.Schema.AgentOperation` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/checkpoint.ex` | `Beamlet.Agent.Storage.Schema.Checkpoint` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/command.ex` | `Beamlet.Agent.Storage.Schema.Command` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/event.ex` | `Beamlet.Agent.Storage.Schema.Event` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 |
| `apps/beamlet_agent_storage/lib/beamlet/agent/storage/schema/operation.ex` | `Beamlet.Agent.Storage.Schema.Operation` | 内部 Ecto schema t（含未插入 nil）、changeset/2、框架生成访问；保持 moduledoc false，普通中文注释说明须通过门面校验，不机械复述字段。 Agent Operation 是只读联接投影，不能代替 Actions 写入口。 |

## 文档与关键边界

- `apps/beamlet_actions_storage/README_zh.md`：职责/真实依赖、authority/journal format3 安装和运行前提、源代码核验的 prepare/replay/fetch/reopen 示例、错误与根验证入口。无既存英文 README，不加断链。
- `apps/beamlet_agent_storage/README_zh.md`：保留已有 format3/事务/恢复约束，补中文入口、create/input/history 示例、不可变继承和投影/分页限制，链接已有英文 README。
- 上表36源路径：模块/API/类型和关键注释。父级持久化专题属于 root-docs 所有者，本批不写应用外专题。

Operation 与 accepted Result 属 Actions；Agent 独立消费引用才推进控制。参与者要求同 Repo，错误须整组回滚。继续后重新读取派发绑定，原 command 响应不刷新。fork 不复制执行，保留原所有权，清单不递归父历史但须保留引用事实；无 GC。检查点是可丢缓存，分页无跨页事务，Agent seq 不是 Operation 接受高水位。无自动业务重试、旧格式回退或外部 exactly-once 保证。

## 实际验证

- OTP29 / Elixir1.20.4 可用，无新增依赖。
- `mix format <36个显式源路径>` 及同范围 `mix format --check-formatted` 通过；未全项目格式化。
- `git diff --check` 通过；`git diff --cached --name-only` 为空。
- `elixir /tmp/domain-ast.exs` 通过：36文件与编辑前 `/tmp/domain-storage-baseline/` 比较，递归忽略 doc/moduledoc/typedoc 与位置元数据，AST 全同。临时脚本/基线不属交付。
- 两份 README 相对链接存在性检查通过；示例参数对照源码/测试，未运行创建数据集的文档示例。
- `mix test apps/beamlet_actions_storage/test apps/beamlet_agent_storage/test` 退出2，seed538499。Actions：10 passed / 7 PostgreSQL excluded；Agent Storage：40/64 passed，24个 PostgresContractTest 因缺少 BEAMLET_PG_SOCKET_DIR 在 setup 失败。该模块未打 postgres_db 标签，不能靠默认 exclude 规避；README 已注明完整套件需要私有 PG。SQLite 争用测试输出 database is locked 日志但断言通过；既有 test/support/contract_fixture.ex test_load_filters 提示保留。
- 测试触发领域应用18+18文件编译成功；不等同独立 warning-fatal 全项目编译。
- 完整 compile --warnings-as-errors、contracts scanner、Credo/Dialyzer、全项目测试、Agent fork/history/export 执行留父级集成，本批未运行；未改测试以绕开前置失败。

## 剩余风险与交接

文档和逐文件交付完整；PG 验证受环境阻塞，24失败须保留，父级配置可丢弃集群后验证。已通过 intercom 通知父级，未重试或修改业务。完整质量门禁、根/专题术语同步及中文阶段验收仍由父会话完成，不代表整个中文任务完成；英文阶段未启动。无新增产品授权需求。
