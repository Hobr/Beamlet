# 计算、Invocation 与 Effect 契约

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
| InputEnvelope | 稳定 input_id、正数 queue_seq、kind、应用载荷、来源信息；内部后续推进附带预期 state_revision，不确定性通知附带通知标识与关联的执行修订号 |
| Run 快照 | definition_ref、state、state_revision、input_cursor、progress、scope_descriptor、mode、lifetime；终态还包含 finish_result 或有界 failure_reason |
| Effect 意图 | effect_ref、来源 Run / 步骤 / 调用序号、Invocation、生效配置、已捕获的声明引用 / 契约版本 / 可重复执行条件 / 生效失败含义（见[能力声明](./capability-composition.md#failure-declaration)）；可变执行记录另含 execution_revision |
| Attempt | attempt_ref、effect_ref、提供者 / 资源 / 代次绑定、execution_owner_ref、原始执行授权证据；执行主体引用为不透明二进制，不是 PID |
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
| finish | finished | 没有未决 Effect 或未处理回复时，原子保存 finish_result 并令 lifetime 为 finished |

过期的内部后续推进记录应被明确处置，不得基于更新的修订重新求值。导入或派生的 ready 状态重建新的分支本地后续推进记录；原 Run 恢复时使用其已提交记录。finished 检查点不得静默重启。

Effect 状态为 pending、executing、unknown、outcome_recorded 或 consumed。executing 表示执行尝试已获授权，不表示操作已经实际开始；它可以伴有更早执行尝试的 unknown 证据。Attempt 状态为 admitted、unknown 或 observation_recorded；证据与结果单独记录。执行与裁定转换由[权威层契约](./authority-and-recovery.md)负责。

### 输入调度与游标

外部输入、Reply（包括不确定性通知）和内部后续推进共享 Run 本地的有序收件箱。queue_seq 由权威层在插入提交中单调分配，不使用客户端时间或提供者完成时间排序。一个步骤最多选择最小的未处置 queue_seq；不得优先跳过队首去消费回复或后续推进。invoke 中各 Invocation 按返回列表的顺序分配标识，但回复按权威插入顺序入队。

input_cursor 表示已连续消费或明确处置的最后一个序号。成功的 CommitStep 原子更新业务状态、输入处置、游标、Effect 与新的后续推进记录。新后续推进排在已存在输入之后，所以连续返回 continue 不会越过已接收输入。ready / waiting 描述是否安排了后续推进，不限制已入队普通输入的消费；mode 与 lifetime 决定是否允许推进。

内部后续推进只在其预期 state_revision 等于当前状态修订号时调用 step。过期记录由 CommitStep 的内部处置变体记录 stale_continuation，推进游标和历史修订号，不调用 step，也不增加状态修订号。普通外部输入和 Reply 不因状态修订变化而自动丢弃。所有内部处置仍受当前纪元、active / open 与队首游标条件约束。

只有按[证据优先规则](./authority-and-recovery.md#monitor-evidence-order)实际进入 unknown 时生成通知；同一 Attempt 确定观测后的迟到监视器报告不重新通知。每次进入 unknown 生成一个稳定通知标识，重复报告同一次不确定性不追加通知。通知与终局回复是不同输入。通知尚未消费而终局结果已提交时，在该通知到达队首后，以 CommitStep 内部处置变体记录 obsolete_uncertainty，不再向定义投递过时的 unknown；已经消费的通知保留历史，后续终局回复仍正常入队。宿主已基于通知求值但尚未提交时，CommitStep / FailRun 还须检查该通知没有被终局结果取代；被取代的提案返回 stale_permission，不提交业务状态、新 Effect 或定义故障，随后明确处置原通知。输入 ID、游标和执行结果去重分别负责不同层次的重复抑制。

### 终态与定义故障

finish 只在提交该步骤后，Run 创建的所有 Effect 均为 consumed、所有已入队回复均已消费或明确处置时合法；当前步骤可以消费最后一条终局回复并同时结束。消费 unknown 通知不能满足这一条件。未决工作使提交返回 invalid_transition，整个步骤提案不提交，保留原状态与输入。

合法 finish 原子保存返回值、令 lifetime / progress 为 finished、关闭输入与新授权入口，并将剩余外部输入和内部后续推进记录标为 unprocessed / run_finished，同时更新连续处置游标。已有历史与结果不被删除。

权限与修订号有效时，定义请求非法 finish 是已确认的步骤转换故障：先返回 invalid_transition、不提交该步骤，随后由当前宿主条件提交 FailRun，记录 invalid_step_transition。不得无限重试同一非法提案，也不得跳过该队首输入去消费后续回复。过期权限或提交竞态本身不构成定义故障。

定义抛出可观察异常、返回非法 step_result，或超过已配置的步骤时间 / 堆预算时，当前宿主提交条件 FailRun：保留最后已提交的业务状态，令 lifetime / progress 为 failed，保存有界 failure_reason，并将当前及剩余输入标为 unprocessed / run_failed，同时更新连续处置游标。没有成功转换，因此不新增 Effect、不把故障输入记为成功消费。初始契约不自动重复执行这些已确认的定义故障；需要修正输入或代码时，从更早稳定边界显式创建分支。

计算宿主丢失或未提交提案丢失不自动构成定义故障，替代宿主可以从已提交输入重新求值。failed 不允许 resume 重启、业务推进或新 Attempt；已授权执行与迟到观测仍按原证据记录。新增回复保留为 unprocessed / run_failed，可检查但不调用 step，也不将 Effect 标为 consumed。failed 快照不属于初始可导入激活的稳定快照类型。

### 标识与捕获

建议的内部 Effect 标识分配方式：Run 标识 + 已提交步骤序号 + 调用序号。Attempt 额外加入权威层序号；所有权纪元不属于逻辑标识。

移动计算宿主时保留标识。新分支获得新 Run 标识，用于后续 Effect。继承的已完成历史保持只读。

能力门面接口仅构造数据，不执行 I/O。状态转换不得直接读取时钟、随机数、邮箱或运行时资源；应通过能力获取观测。未提交的转换可以重新求值。权威层创建前，规范化并捕获生效配置；持久化意图保持不可变。

<a id="failed-audit"></a>

### 已评审补充：failed 的证据保留边界

FailRun 关闭业务推进入口，不改变既有 Effect 意图、原始授权、已记录观测或最后业务状态。failed 不可 resume、CommitStep、创建新 Attempt、settle 或 allow_repeat；追加有来源的审计证据仍遵循原裁定条件。

原始授权主体可以在 failed 后首次进入已授权调用或补充迟到观测。有效观测仍按[证据归约](./authority-and-recovery.md#3-契约)决定是否记录唯一终局结果。其回复保留为 unprocessed / run_failed，不调用定义、不记为成功消费、不使原来未消费的 Effect 变为 consumed。unknown 或仅局部失败可以长期作为可检查的审计事实存在；不得为了清空待处理列表而删除证据、伪造失败、恢复业务或赋予终态人工裁定 / 取消功能。终态人工 settlement 仍属暂缓事项。

必需断言包括：failed 时保留 unknown；迟到局部失败仍未决；迟到有效成功或逻辑失败可记录一条未处理回复；控制恢复、重复许可和业务消费均被拒绝。已在失败前合法消费的历史保持原样。

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
| 存在未决 Effect 或未处理回复时结束 | invalid_transition；整个步骤不提交，保留状态与输入 |
| 定义已确认异常、非法返回或超过步骤预算 | 条件 FailRun；记录 step_exception / invalid_step_result / step_resource_limit |
| 向已结束 Run 提交输入或请求恢复 | run_finished / run_failed |

不确定性通知是普通的持久化 Reply / 输入，不带终局权威结果。消费该通知不代表 Effect 已处理完毕。裁定通过调用引用记录证据或明确的重复执行权限，不改写原始意图或历史。

裁定使用 InvocationRef、expected_execution_revision、稳定 command_id 和有界 decision。允许的 decision 为追加审计证据、显式确定终局结果或一次性允许重复执行，具体前置条件、竞态和原子记录见[权威层裁定契约](./authority-and-recovery.md#invocation-resolution)。证据追加不会把未知自动解释为成功或失败；允许重复执行不改写原始意图。

检查接口采用带修订号的有界分页。快照查询与历史 / 执行尝试查询返回带类型的投影，而非后端文件。调用投影包含 invocation_ref、执行状态、execution_revision 与裁定依据，调用方无需读取 Effect 记录即可构造条件裁定。渲染使用方不独立解码账本载荷。

## 5. 正例、基础场景与反例

正例：Agent 设置生成普通 Invocation，其已提交 Reply 更新普通 Agent 状态。子 Agent 提供者通过稳定键创建通用 Run。

基础场景：创建初始 ready 快照，由 `:continue` 产生首次调用请求。

反例：纯状态转换直接调用提供者；为重试创建新 ID；或者将 unknown 视为已知的终局失败。

## 6. 必需测试

<a id="s2"></a>

### S2 — 显式推进与重启

断言状态、输入消费、新 Effect 或后续推进记录在同一次提交中完成。提交前丢失状态提案后，重新求值且不执行外部操作。重启 ready / waiting 快照后，保留正确的推进指令与游标。Agent 定义仅接收普通回复。

验证相同键与相同载荷的创建和输入去重、同键载荷变更冲突、重复后续推进记录抑制，以及终态输入的明确处置。重复的已提交回复不得使状态推进两次。

| 初始条件 / 事件 | 必须提交或保留 | 禁止行为 |
| --- | --- | --- |
| ready 的后续推进后，已有外部输入和两条回复；不同来源交错入队 | 按 queue_seq 逐条处置；新后续推进追加到队尾 | 按来源优先级跳队或重新投递已消费输入 |
| 外部输入改变状态，使队列中的旧后续推进过期 | stale_continuation、游标与历史修订号；业务状态修订号不变 | 调用旧后续推进或产生新 Effect |
| unknown 通知先提交，终局回复在该通知消费前提交 | 通知到达队首后明确记为 obsolete_uncertainty，终局回复消费一次 | 跳队处置、在已知终局结果后投递过时 unknown |
| 宿主对 unknown 通知求值后，终局结果先于步骤 / 故障提交 | stale_permission；不提交旧提案，再明确处置通知 | 提交基于过时 unknown 的新 Effect 或 FailRun |
| 最后一条终局回复的消费步骤返回 finish | 原子保存 finish_result、消费结果及终态 | 丢失返回值或先终止再消费结果 |
| 存在 pending / executing / unknown Effect 时返回 finish | invalid_transition；不提交步骤，随后可条件 FailRun，保留原状态、输入和工作 | 关闭授权入口后丢失未决工作，或无限重试非法提案 |
| step 异常、非法返回或超过步骤预算 | FailRun、最后已提交状态、未处理输入与故障原因 | 自动重复同一已确认故障或提交部分转换 |
| failed 后，先前已授权工作报告结果 | 保存观测、权威结果和未处理回复 | 重启定义、丢弃结果或把未处理回复记为 consumed |

## 7. 错误与正确做法

~~~elixir
# 错误：在可重新求值的状态转换中执行提供者 I/O。
response = HTTPProvider.request(arguments)

# 正确契约：门面接口返回 Invocation 数据。
call = LLM.chat_call(arguments, reply_key: :chat)
{:invoke, next_state, [call]}
~~~

示例中的门面接口是目标声明接口，不表示 HTTP / LLM 模块已经实现。
