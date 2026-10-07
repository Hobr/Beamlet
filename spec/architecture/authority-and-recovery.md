# 权威存储、执行尝试与恢复

状态：`architecture-v1` 已评审基线；本次协议补充待评审，见[架构索引](./index.md)。Ra 是实现建议，仍有待完成的验证要求。

## 1. 适用范围

定义权威状态与历史、条件提交、所有权隔离、执行尝试授权，以及不确定的外部操作结果。分布式成员关系和本地进程注册都不决定权威所有权。

## 2. 接口签名

~~~text
Authority.command(domain_ref, envelope) -> {:ok, receipt} | {:error, error}
Authority.read(domain_ref, query, consistency: :consistent) -> {:ok, projection} | error

command.body =
  StartRun | AppendInput | CommitStep | FailRun | AdmitAttempt | RecordObservation
  | ResolveInvocation | ClaimHost | Suspend | Resume | Fork | Import
~~~

这些命令是类型封闭的数据变体，不是序列化函数或任意数据库更新。所有修改命令信封包含 command_id 与逻辑载荷；条件命令还包含预期修订号与权限。

## 3. 契约

### 配置

目标应用配置位于 `:beamlet_lib` 下：

| 配置键 | 约束 |
| --- | --- |
| roles | 配置为 interaction、compute、execute、authority 的子集 |
| authority_domain | 本次部署共享的稳定二进制标识 |
| authority_nodes | 运维方选定的节点标识与持久化位置 |
| definition_registry | 已注册的可信计算定义、代码与模式引用 |
| codec_limits | [生命周期与归档](./lifecycle-and-archives.md)中规定的正数、有界数据配置 |
| step_limits | 正数 step_timeout_ms 与 step_heap_words；在受监督的步骤工作进程中执行纯转换并限制资源 |

不规定新的环境变量协议。部署适配器必须在应用启动前验证环境变量到配置的转换。

容忍单个权威节点及其磁盘丢失的配置，需要足够的持久化副本与独立故障域；首个 Ra 目标为三个投票节点。更弱的开发拓扑不得宣称提供这一保证。

### 原子记录与命令

| 命令体 | 前置条件 | 一同变更的记录 |
| --- | --- | --- |
| StartRun | 有效定义、状态、作用域与创建键 | 标识、初始快照与推进状态、收件箱与回执 |
| AppendInput | Run 接受输入；有效的稳定输入键与数据 | 有序输入与回执 |
| CommitStep | 当前所有权纪元、active / open Run、预期状态修订号与队首游标；未知通知仍有效，结束还须无未决工作 | 状态与推进状态、输入处置、新 Effect 或后续推进记录、历史与边界；内部处置变体仅更新处置、游标与历史 |
| FailRun | 当前所有权纪元、active / open Run、匹配的状态修订号与仍可投递的队首输入、有界定义故障 | failed 终态与原因、未处理输入处置与游标、历史与回执；保留业务状态、Effect 与授权证据 |
| AdmitAttempt | active / open Run；当前编排权限与预期 execution_revision；合格提供者与执行主体；无终局结果或其他 admitted Attempt；有效恢复条件 | 执行尝试序号、精确绑定与授权证据、执行修订号；适用时消费一次性重复执行权限 |
| RecordObservation | 可识别的原始执行尝试、执行主体与绑定、匹配的不可变意图、有效观测 | 执行尝试证据与执行修订号；有充分依据时，一同记录权威结果与一条终局回复 |
| ResolveInvocation | 已授权的调用引用、预期 execution_revision、有界 decision；具体条件见裁定表 | 审计证据、终局结果与回复或一次性重复执行权限、执行修订号、历史与回执 |
| Suspend/Resume/ClaimHost | 已授权的条件控制；Resume 仅适用于 open Run | 模式与宿主权限、用于隔离旧提案的纪元 |
| Fork/Import | 稳定源边界或已验证归档、兼容目标 | 新标识、快照、派生关系与回执 |

状态、输入消费与新 Effect 创建必须在同一次提交中完成。意图和执行尝试权限提交前，不得执行调用请求。

状态修订号跟踪业务转换。输入、结果或控制证据变化也会改变历史修订号。Effect 的 execution_revision 跟踪其授权、观测与裁定变化，用于独立检查执行竞态；不能用 Run 的状态修订号代替。三者均不等同于后端 Ra 索引。

### 纪元与回执

接管或控制变更使过期的状态推进提案和新 Attempt 授权提案失效，不撤销已经提交的 Attempt 授权。计算宿主变更、暂停或 Run 进入终态后，原始执行主体仍可执行已获授权的工作并报告合法观测；不得将新的 Run 纪元作为拒绝这些结果的理由。

稳定命令 ID 用于逻辑修改去重。同一权威域内 command_id 唯一，命令类型、目标引用和原始条件字段都是规范化逻辑载荷的一部分。已保留键下的数据发生变化时返回 key_conflict。通过接入授权检查后，先查已提交回执，再检查当前纪元、修订号与生命周期条件：相同键与载荷返回原回执，不重新执行命令。这样，暂停、接管或终态发生后的原键重试也能查明先前提交。为所有支持的重试与恢复路径保留键和证据，不得仅因较短 TTL 到期而删除。

回执证明提交完成，不证明外部操作成功。已提交命令请求但无法确定提交状态时，返回 commit_unknown。重新读取回执，或使用原键与原载荷重试。不得通过创建新的创建请求或操作标识来规避不确定性。

恢复、分支与导出必须依据一致性读取。本地副本视图、普通缓存视图或领导者视图不足以作为权限依据。正确性不得依赖节点时钟同步。

### 执行主体、分发与恢复

每个 Attempt 在 AdmitAttempt 中绑定一个预先创建的工作进程实例及其 execution_owner_ref。该引用由可信运行时为实例分配，跨实例不复用，可持久化但不包含 PID；本地注册仅把它映射到当前实例，不能使替代实例继承旧授权。提供者、资源、代次和执行主体一起构成精确绑定。

同一实例必须在进入 Effect.invoke 前，将该 Attempt 的本地调用状态从未开始改为已进入；重复分发、重复回执或重复消息只能查询状态或重报已有观测，不能再次调用。一个实例存续期间的标记不得因任务重启而清空；实例退出后的替代工作进程获得新的 execution_owner_ref，不能重建旧实例或重用其 Attempt。原键查询到已提交授权回执不是新的调用许可。

分发确认丢失时，先查询同一实例或权威证据。原实例存活时可向它重复投递；原实例丢失或状态无法确定时，记录 unknown，保留可能已经执行的事实。不得把同一 Attempt 转交另一个实例。仅在符合恢复条件时，创建绑定新实例的新 Attempt。权威层在预期 execution_revision 下检查并串行授权；存在 admitted Attempt 时不主动增加并行 Attempt。unknown 的旧实例可能仍在物理执行，新的恢复尝试必须把这一可能性纳入重复执行条件。

同一次调用的稳定请求令牌由 Effect 逻辑标识与操作所需的去重域关联，不随 Attempt 或执行主体改变。新 Attempt 不得换用新令牌来规避提供者去重。调用前仍须检查绑定代次与资源；预检拒绝的未执行证明只覆盖该 Attempt，不能证明更早的 Attempt 未执行。

### 结果规则

运行时观测必须包含稳定 observation_id、Attempt 引用、原始授权与绑定证据，以及以下一种有界载荷。重报同一 observation_id 与载荷不重复改变记录；同键不同载荷返回 key_conflict。可信恢复监视器可以报告执行主体失联的 unknown 证据，但不得把断连报告构造成提供者成功、失败或未执行证明。

Effect 创建时为 pending，AdmitAttempt 后为 executing。有效的 succeeded、failed 或 not_executed 观测将对应 Attempt 标为 observation_recorded；unknown 观测将其标为 unknown，后来经过验证的观测仍可补充。唯一终局结果提交后 Effect 为 outcome_recorded，终局回复由 CommitStep 成功消费后才为 consumed；通知消费与 run_failed 处置都不能产生 consumed。

操作可能已经执行后，仅当具备幂等性、适用的去重保障或明确允许重复执行时，操作声明才允许自动重试。保留请求语义以及实际去重域和保留期。声明本身不能延长提供者已过期的保证。

权威结果记录与回复插入必须原子完成。重复观测不得投递第二条终局回复。冲突与迟到证据仍可检查；已消费结果不得覆盖。

结果未知与已确认失败、已确认未执行是不同情况。超时、nodedown 和重试次数耗尽都不是未执行证据。后续执行尝试失败，不能确定此前可能已执行尝试的结果。

持久化不确定性通知可以进入普通 Reply 路径，而不产生最终完成结果。每次进入 unknown 原子记录稳定通知标识与一条通知；仍处于同一次 unknown 的重复报告只追加新证据，不再通知。通知的去重及过时处置遵循[输入调度契约](./computation-and-effects.md)。

| 观测类型 | 含义 | Effect 与回复处置 |
| --- | --- | --- |
| succeeded(data) | 操作契约认可的成功结果 | 无既有终局结果时原子记录 {:ok, data} 与终局回复；不清除其他 Attempt 的证据 |
| failed(data) | 已确认的操作失败，不等于未执行 | 仅在不存在更早未决执行、且声明足以确定整个逻辑操作失败时记录 {:error, data}；否则保持 unknown |
| not_executed(evidence) | 可以验证该 Attempt 未进入外部调用 | 没有其他未决执行时回到 pending，可安全重新授权；否则保持 unknown，不产生终局回复 |
| unknown(evidence) | 执行或结果无法确认 | Attempt 标为 unknown；没有终局结果或其他 admitted Attempt 时 Effect 进入 unknown，产生非终局通知 |

已有终局结果后，新观测只更新审计证据，不能覆盖结果或新增终局回复。恢复 Attempt 的失败或预检拒绝不能消除更早的未知执行。所有允许记录的结果仍须通过操作回复模式与数据边界验证。没有有效结果可记录时，保留不确定性。

<a id="invocation-resolution"></a>

### 调用裁定

ResolveInvocation 的载荷包含 invocation_ref、expected_execution_revision 和 decision。调用引用必须解析到该 Run 的调用；控制边界逐操作授权。除已提交回执的原键重试外，执行修订号不匹配返回 stale_permission。

| decision | 前置条件 | 原子记录与结果 |
| --- | --- | --- |
| {:record_evidence, evidence} | 调用存在；证据有界、带来源且符合已注册审计模式；允许暂停或终态 | 追加审计证据与回执；不单凭该决策改变终局结果或授权执行 |
| {:settle, {:ok, data} 或 {:error, data}, evidence} | Effect 为 unknown、无 admitted Attempt、Run 为 open；结果符合回复模式，证据说明裁定者与依据 | 保留裁定前证据，记录唯一终局结果、outcome_recorded 与一条终局回复；允许在 suspended 下记录 |
| {:allow_repeat, justification} | Effect 为 unknown、无 admitted Attempt、Run 为 open；有明确承担可能重复执行后果的依据与授权 | 记录仅供下一次 AdmitAttempt 消费的一次性权限；Effect 保持 unknown，不立即执行、不插入终局回复 |

重复执行权限绑定当前 Effect 与不可变意图，不改变参数、配置、资源约束或提供者兼容条件；AdmitAttempt 在同一提交中消费它。后续再次进入 unknown 需要重新评估声明或获取新的权限，不能把一次裁定解释为永久无限重试。暂停期间可记录该权限，但恢复前不能授权新 Attempt。

终局结果先提交时，使用过期修订号的 settle / allow_repeat 返回 stale_permission；重新读取并以当前修订号提交新的决策时返回 already_resolved。settle 先提交时，后到观测只按迟到证据规则保存，不覆盖结果。原键原载荷重试始终遵循回执优先规则。修订号冲突后不得修改原 command_id 的载荷，新的逻辑决策须使用新键。record_evidence 不代替经过验证的 RecordObservation，也不作为执行前审批 API。

工作进程通过权威层记录结果，不依赖原计算宿主 PID。丢失的通知通过权威待处理工作与收件箱修复。failed Run 的结果与未处理回复按[终态契约](./computation-and-effects.md)保留。

## 4. 验证与错误矩阵

| 条件 | 结果 |
| --- | --- |
| 状态提案来自过期纪元或修订号 | stale_permission；不改变状态或调用 |
| 暂停或进入终态后请求执行授权 | invalid_transition / stale_permission |
| 缺少已提交意图，执行尝试令牌未知，或执行主体 / 绑定不匹配 | invalid_admission |
| 已有 admitted Attempt，或授权提案的 execution_revision 过期 | invalid_transition / stale_permission；不新增 Attempt |
| 同一命令键对应不同载荷 | key_conflict |
| 重复终局观测 | 返回已有处置结果；不新增回复 |
| 迟到观测与已有结果冲突 | 记录冲突证据；权威回复不变 |
| 新的终局裁定或重复执行决策针对已终局调用 | 先校验 execution_revision；当前修订下返回 already_resolved，不覆盖结果或新增回复 |
| 裁定类型、证据、结果或来源无效 | invalid_data；不修改调用 |
| 发送前没有可用权威访问路径 | authority_unavailable |
| 提交响应丢失，或修改请求提交超时 | commit_unknown |
| 重试会改变去重域，或去重保护已经过期 | 保持 unknown；不自动授权 |
| 外部工作完成后，结果无法验证或记录 | 保留不确定性；不得截断结果或宣称成功 |

## 5. 正例、基础场景与反例

正例：提交意图、授权执行尝试、将结果记录到权威收件箱，再提交结果消费。各阶段之间丢失计算宿主，不会丢失已接收数据。

基础场景：全部角色位于同一节点，逻辑标识与回执仍保持相同语义。

反例：缓存 PID 作为所有权；使用发出即忘消息作为持久化确认；在复制状态应用或事务中执行外部操作；将所有超时都称为失败。

## 6. 必需测试

<a id="s3"></a>

### S3 — 远程执行期间丢失计算宿主

计算宿主 A 为提供者 B 提交操作。B 执行期间终止 A。B 向权威层报告；替代宿主 C 读取并消费同一个权威结果。断言 Run / Effect 标识稳定，且不依赖 A 的 PID。

<a id="s4"></a>

### S4 — 各个崩溃边界

在步骤提交前、步骤提交后但通知前、执行授权后、外部操作后但结果记录前，以及记录后但投递前注入故障。断言允许出现的 pending / unknown / 已记录状态，并确认恢复不会因传输丢失而推断未执行。

| 初始条件 / 故障 | 必须提交或保留 | 禁止行为 |
| --- | --- | --- |
| 两个控制器使用同一 execution_revision 请求授权 | 最多一个成功授权；另一个得到旧权限或状态错误 | 并发创建两个 admitted Attempt |
| 同一 Attempt 被重复投递给同一执行主体 | 最多一次 Effect.invoke；已有观测可重报 | 重复提供者调用 |
| 工作进程在调用前或调用后退出，无法确认具体位置 | 原 Attempt 保持 unknown；恢复使用新主体与新 Attempt | 重建原主体并重放旧授权 |
| 授权回执丢失，随后 Run 暂停或宿主接管 | 原键原载荷查询返回原回执；新授权仍受当前条件约束 | 将回执查询当作新调用许可 |
| 结果回执丢失或通知丢失 | 重报观测 / 修复收件箱，不新增终局回复 | 创建新 Effect 或重复消费结果 |

<a id="s10"></a>

### S10 — 指定权威节点与网络分区

仅让选定的存储节点子集参与投票。在支持的配置下，永久移除一个权威节点及其磁盘，恢复已确认状态。对权威组制造网络分区；断言没有相互冲突的权威推进、少数派执行授权或虚假回执，并验证安全恢复连接和旧所有者拒绝行为。

<a id="s11"></a>

### S11 — 按声明恢复与迟到证据

使用同一 Effect 标识和新 Attempt 重试可重复执行的操作。没有重复执行权限的操作保持 unknown，直到显式裁定。替换提供者或去重域，或使保护期到期，拒绝自动重试。断言迟到冲突证据不能改变已消费结果，也不能将第二条回复加入队列。

| 初始条件 / 决策 | 必须提交或保留 | 禁止行为 |
| --- | --- | --- |
| 旧 Attempt 为 unknown，新 Attempt 报告 failed 或 not_executed | 保留旧未知证据；不得据此确定整体失败 | 把新尝试的失败解释为旧工作未执行 |
| unknown 下追加审计证据 | 来源、证据、执行修订号与回执 | 仅因追加证据就执行或产生终局回复 |
| suspended / open Run 对 unknown 显式 settle | 唯一终局结果、证据与回复原子提交；恢复后消费一次 | 暂停期间推进业务状态 |
| 一次 allow_repeat 后，两个控制器请求新 Attempt | 最多一次权限消费与新授权；原意图和稳定请求令牌不变 | 同一许可授权多个新 Attempt |
| 终局观测与 settle 竞争 | 提交顺序与 execution_revision 决定胜者，另一路保留冲突证据或返回错误 | 两个终局回复或覆盖已消费结果 |
| 已终局 / consumed 调用收到新的 settle 或 allow_repeat | stale_permission 或 already_resolved；原历史保持 | 重新执行已终局调用 |

### 存储实现验证要求

Ra 是提议方案，尚未安装或测试。运行时发布前，必须固定受支持版本，并证明它能在实际 OTP 29 / Elixir 1.20 工具链上编译，以及跟随节点磁盘同步、法定人数应用与回复、快照与日志恢复、回执、旧权限隔离和暂停竞态均符合要求。

公共历史日志与检查点作为应用记录，在后端压缩整理后继续保留。初始扩展上限为一个权威组和保留历史的状态机；分片需要测量并修订实现决策。

## 7. 错误与正确做法

~~~text
错误：节点断连 -> 使用新 ID 重试操作。
正确：保留原 Effect / 执行尝试证据 -> 按声明恢复 -> 仅在允许时创建新执行尝试。

错误：先更新状态，随后发送或存储其操作。
正确：通过条件提交，原子记录状态 + 已消费输入 + 新 Effect。

错误：新计算宿主纪元拒绝全部旧工作进程结果。
正确：使旧宿主的推进权限失效，依据原始已授权执行尝试验证观测。
~~~
