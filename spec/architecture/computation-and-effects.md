# 计算、Invocation 与 Effect 契约

状态：已评审的目标契约；接口签名与载荷用于指导后续实现。

## 1. 适用范围

定义面向业务的状态转换、引用标识、共享记录模式与通用公共接口。权威层转换由[权威存储与恢复](./authority-and-recovery.md)定义。

## 2. 接口签名

计算定义的目标返回值：

~~~elixir
@callback step(portable_term(), application_input()) ::
  {:continue, portable_term()}
  | {:wait, portable_term()}
  | {:invoke, portable_term(), nonempty_list(invocation())}
  | {:finish, portable_term(), portable_term()}
~~~

应用输入为 `:continue`、`{:external, data}` 或 `{:reply, reply_key, invocation_ref, {:ok, data} | {:error, data} | {:unknown, evidence}}`。持久化输入信封与游标由业务定义之外的运行时处理。

公共门面接口的目标操作：

~~~text
Beamlet.start_run(definition_ref, initial_state, scope_descriptor, opts)
Beamlet.submit_input(run_ref, input, opts)
Beamlet.suspend(run_ref, opts)
Beamlet.resume(run_ref, opts)
Beamlet.move(run_ref, host_ref, opts)
Beamlet.inspect_run(run_ref, query)
Beamlet.fork(run_ref, boundary_ref, opts)
Beamlet.export(run_ref, boundary_ref, profile, opts)
Beamlet.import_archive(binary, bindings, profile, opts)
Beamlet.resolve_invocation(run_ref, invocation_ref, decision, opts)
~~~

修改状态的调用返回 `{:ok, receipt}` 或 `{:error, error}`。导出返回 `{:ok, binary}`；检查返回 `{:ok, projection}`。错误始终包含稳定错误码与有界详情。`commit_unknown` 表示命令可能已经提交。

## 3. 契约

所有引用都是不透明的可移植数据，不使用 PID。调用方不得解析其内部表示，也不得将 InvocationRef 等同于内部 EffectRef。

| 记录 | 必需字段 / 约束 |
| --- | --- |
| DefinitionRef | id 与 logic_version：二进制；state_schema 与 input_schema：已注册的名称 / 版本引用 |
| RunRef | 权威域与 Run 标识；内部编码不透明 |
| Invocation | operation_ref：能力 / 操作 / 版本；arguments：可移植项；reply_key：二进制或允许的静态原子；resource_constraints：已验证数据 |
| Reply | reply_key、invocation_ref、result；不包含 Effect、Attempt 或存储对象 |
| InputEnvelope | 稳定 input_id、正数 queue_seq、kind、应用载荷、来源信息；队列与游标属于内部细节 |
| Run 快照 | definition_ref、state、state_revision、input_cursor、progress、scope_descriptor、mode、lifetime |
| Effect 意图 | effect_ref、来源 Run / 步骤 / 调用序号、Invocation、生效配置、已捕获的可重复执行声明 |
| Attempt | attempt_ref、effect_ref、提供者 / 资源 / 代次绑定、原始执行授权证据 |
| Receipt | command_id、run_ref、history_revision、适用时的 state_revision、操作结果 |
| Error | code：稳定原子或二进制；details：有界可移植数据；不得泄露运行时对象 |

外部来源的引用名称与版本名称使用二进制。已注册代码从可信配置解析，不采用归档提供的 MFA（模块、函数、参数）。

修改状态的 opts 必须包含稳定 command_id，每个逻辑请求只分配一次。追加输入还需要稳定输入键。重试保留原始逻辑载荷；同一键对应不同的规范化数据时，返回 key_conflict。

### 推进状态与生命周期

mode 为 active 或 suspended。lifetime 为 open、finished 或 failed。应用自身阶段保持为不透明状态。

| 步骤返回值 | 提交后的 progress | 行为 |
| --- | --- | --- |
| continue | ready | 提交以 Run / 状态修订号为键的数据式后续推进记录 |
| wait | waiting | 等待普通外部输入或回复输入 |
| invoke | waiting | 将非空调用请求集合原子创建为 Effect |
| finish | finished | 仅在相关完成结果处理完毕后关闭执行授权入口 |

过期的内部后续推进记录应被明确处置，不得基于更新的修订重新求值。导入或派生的 ready 状态重建新的分支本地后续推进记录；原 Run 恢复时使用其已提交记录。finished 检查点不得静默重启。

Effect 状态为 pending、executing、unknown、outcome_recorded 或 consumed。executing 表示执行尝试已获授权，不表示操作已经实际开始。Attempt 状态为 admitted、unknown 或 observation_recorded；证据与结果单独记录。

结束时，剩余外部输入应保留明确的“未处理”处置记录。接收输入不代表已经成功处理。尚未处理完毕的 Effect 完成结果不得静默丢弃。

### 标识与捕获

建议的内部 Effect 标识分配方式：Run 标识 + 已提交步骤序号 + 调用序号。Attempt 额外加入权威层序号；所有权纪元不属于逻辑标识。

移动计算宿主时保留标识。新分支获得新 Run 标识，用于后续 Effect。继承的已完成历史保持只读。

能力门面接口仅构造数据，不执行 I/O。状态转换不得直接读取时钟、随机数、邮箱或运行时资源；应通过能力获取观测。未提交的转换可以重新求值。权威层创建前，规范化并捕获生效配置；持久化意图保持不可变。

## 4. 验证与错误矩阵

| 条件 | 错误码 / 行为 |
| --- | --- |
| 状态、输入、参数或结果无效 / 不可移植 | invalid_data；不得返回虚假回执 |
| 代码或模式未注册 / 不兼容 | incompatible_version |
| 同一命令键或输入键对应的数据改变 | key_conflict |
| 旧修订号或旧所有权权限 | stale_permission |
| 缺少必需资源 | unavailable_resource；保留请求语义 |
| 提交前没有有效权威访问路径 | authority_unavailable |
| 已提交修改请求，但无法确定提交结果 | commit_unknown；查询或使用原键重试 |
| 边界不稳定 | not_stable |
| 存在未处理完毕的完成结果时结束 | invalid_transition；保留状态与工作 |
| 向已结束 Run 提交输入 | run_finished |

不确定性通知是普通的持久化 Reply / 输入，不带终局权威结果。消费该通知不代表 Effect 已处理完毕。裁定通过调用引用记录证据或明确的重复执行权限，不改写原始意图或历史。

检查接口采用带修订号的有界分页。快照查询与历史 / 执行尝试查询返回带类型的投影，而非后端文件。渲染使用方不独立解码账本载荷。

## 5. 正例、基础场景与反例

正例：Agent 设置生成普通 Invocation，其已提交 Reply 更新普通 Agent 状态。子 Agent 提供者通过稳定键创建通用 Run。

基础场景：创建初始 ready 快照，由 `:continue` 产生首次调用请求。

反例：纯状态转换直接调用提供者；为重试创建新 ID；或者将 unknown 视为已知的终局失败。

## 6. 必需测试

### S2 — 显式推进与重启

断言状态、输入消费、新 Effect 或后续推进记录在同一次提交中完成。提交前丢失状态提案后，重新求值且不执行外部操作。重启 ready / waiting 快照后，保留正确的推进指令与游标。Agent 定义仅接收普通回复。

验证相同键与相同载荷的创建和输入去重、同键载荷变更冲突、重复后续推进记录抑制，以及终态输入的明确处置。重复的已提交回复不得使状态推进两次。

## 7. 错误与正确做法

~~~elixir
# 错误：在可重新求值的状态转换中执行提供者 I/O。
response = HTTPProvider.request(arguments)

# 正确契约：门面接口返回 Invocation 数据。
call = LLM.chat_call(arguments, reply_key: :chat)
{:invoke, next_state, [call]}
~~~

示例中的门面接口是目标声明接口，不表示 HTTP / LLM 模块已经实现。
