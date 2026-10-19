# orchestration 中文覆盖交接

STATUS: COMPLETE

范围：runtime 10、agent 21、node 10，共 41 个生产源文件。已逐文件完整读取；三个应用既有英文 README 与 manifest 已读。只增加中文 README、文档属性与解释性注释；保留有效英文，未启动英文翻译阶段。无行为、类型、签名、依赖、配置值、产品字符串或测试修改。未提交、切分支、激活或归档任务。

## 逐文件审阅与说明决定

下表列出实际模块与 public def/defdelegate 名称分组（同名多元数一组）。可见模块的公开类型均补中文说明；无自定义 macro/behaviour callback 声明。OTP init/handle_call/handle_info/terminate 的框架契约保留 @impl/@spec，集中由模块生命周期说明覆盖，不给每个重复协议分支添加机械 doc。内部 false 模块、false 函数的隐藏边界保留，仅补解释性注释；其公开形状类型用于内部跨模块引用，不扩成用户 API。

| 源路径 | 模块及 API 分组 | 中文处理与约束 |
| --- | --- | --- |
| `apps/beamlet_runtime/lib/beamlet/runtime/directory.ex` | `Beamlet.Runtime.Directory`：`start_link`, `limits`, `select`, `snapshots`, `init`, `handle_info`, `handle_call`; 类型 `selection`<br>`Beamlet.Runtime.NodeEndpoint`：`start_link`, `init`, `handle_info` | 隐藏实现保留 false；报告只按本 VM 接收时间老化；发现与排序不预留容量，Gateway 必须再次验证并原子扣减池。<br>隐藏实现保留 false；报告只按本 VM 接收时间老化；发现与排序不预留容量，Gateway 必须再次验证并原子扣减池。 |
| `apps/beamlet_runtime/lib/beamlet/runtime/execution_supervisor.ex` | `Beamlet.Runtime.ExecutionSupervisor`：`start_link`, `init` | 隐藏实现保留 false；Workers 与 Gateway 以 one_for_all 共存亡，旧任务不能跨越新一代容量账本。 |
| `apps/beamlet_runtime/lib/beamlet/runtime/executor_gateway.ex` | `Beamlet.Runtime.ExecutorGateway`：`start_link`, `eligible?`, `init`, `handle_info`; 类型 `durable_envelope`, `admit_message` | 隐藏实现保留 false；本 Gateway 首个处理的停止触发决定来源；只有匹配 shutdown 或请求 kill 后的 DOWN 才是本地停止证据，不能推断上游回滚。 |
| `apps/beamlet_runtime/lib/beamlet/runtime/observation.ex` | `Beamlet.Runtime.Observation`：`now`, `remaining`, `read`, `isolate`; 类型 `failure` | 隐藏实现保留 false；一次性 linked 读取隔离迟到回复；远端预算从执行 VM 的入口开始，调用者放弃不等于远端立即取消。 |
| `apps/beamlet_runtime/lib/beamlet/runtime/operation_coordinator.ex` | `Beamlet.Runtime.OperationCoordinator`：`start_link`, `init`, `handle_info`, `handle_call`; 类型 `durable_status` | 隐藏实现保留 false；每个协调器只发送一次；接受终态后迟到回执只能补证据，不能替换 Result 或再次通知 sink。 |
| `apps/beamlet_runtime/lib/beamlet/runtime/persistence.ex` | `Beamlet.Runtime.Persistence`：`new`, `uuid`, `description`, `prepare`, `receipt`, `evidence`, `result_payload`, `value`; 类型 `t`, `object`, `prepared`, `candidate`, `receipt`, `journal` | 可选持久化接线：authority 先准备并声明发送，执行器先记录 start_intent，authority 接受唯一 Result 后才通知 sink。通过 Runtime 的 child spec 显式启动监督树；本模块不启动 Repo。未决执行和未知提交均不授权再次发送，消费结果由调用方编排。 |
| `apps/beamlet_runtime/lib/beamlet/runtime/report.ex` | `Beamlet.Runtime.Report`：`valid?`, `labels?`, `label?`, `pools?`, `validate_configuration!`; 类型 `pools`, `registrations`, `placement`, `t` | 隐藏实现保留 false；报告不携带 settings/provider PID；完整信封预算与注册验证共同限制广播内容。 |
| `apps/beamlet_runtime/lib/beamlet/runtime/shared_supervisor.ex` | `Beamlet.Runtime.SharedSupervisor`：`start_link`, `init`<br>`Beamlet.Runtime.Limits`：`new`; 类型 `t` | 显式启动的共享基础设施，one_for_all 重启使已有 Ref 失效；临时协调器不恢复业务工作。<br>隐藏实现保留 false；同文件内部 endpoint/limits 的校验与监督协议由公开入口说明，不增加公开文档。 |
| `apps/beamlet_runtime/lib/beamlet/runtime/worker.ex` | `Beamlet.Runtime.Worker`：`run`; 类型 `result` | 在受监督任务内调用 Handler，独立转发辅助进度并限制生产额度。Handler 自行拥有其额外子进程及外部资源；协作取消标记不证明外部停止。 |
| `apps/beamlet_runtime/lib/beamlet/runtime.ex` | `Beamlet.Runtime`：`observation`, `child_spec`, `submit`, `evidence`, `status`, `cancel`, `ack`; 类型 `options`, `submit_options`, `snapshot`, `observed_report`, `observation`, `command`, `control_result` | 显式监督的一次尝试分布式执行入口。先在宿主监督树安装 `{Beamlet.Runtime, options}`；默认仅发现，`execution: true` 才启动执行器。提交成功仅表示取得协调器 Ref，执行结果异步投递；不自动重试或重放。取消请求、超时和本地 worker 退出均不能证明外部副作用回滚。 |
| `apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex` | `Beamlet.Agent.AuthoritySupervisor`：`start_link`, `init` | 显式 authority 身份岛，以 one_for_all 耦合 Registry、Resources、Delegations 和 Agents。Registry 丢失使所有临时 Agent 身份失效；模型 provider 注册表是本地可信配置，加载库不会启动该树。 |
| `apps/beamlet_agent/lib/beamlet/agent/context_builder.ex` | `Beamlet.Agent.ContextBuilder`：`complete_boundary`, `observation`, `reply`, `build`, `materialize` | 逐个读取、校验来源，再交给纯 Core 增量转换上下文；前缀超限或损坏后不再读取后续来源。未消费的输出不进入上下文。 |
| `apps/beamlet_agent/lib/beamlet/agent/delegation.ex` | `Beamlet.Agent.Delegation`：`launch`, `run` | 隐藏实现保留 false；每个子项有独立所有权控制器；父级授权 startup 后才输入，停止/失联触发清理但不证明外部执行回滚。 |
| `apps/beamlet_agent/lib/beamlet/agent/discovery.ex` | `Beamlet.Agent.Discovery`：`budget`, `bytes`, `now`, `remaining`, `valid_id?`, `list`, `lookup`, `query`, `query_local`; 类型 `descriptor` | 隐藏实现保留 false；身份读取与 authority 监督岛隔离；lookup 校验真实 Ref，不构造替代实例；初始连接预检不能阻止后续 OTP 重连。 |
| `apps/beamlet_agent/lib/beamlet/agent/display.ex` | `Beamlet.Agent.Display`：`metadata?`, `annotate`, `project`; 类型 `metadata`, `snapshot` | 实时上下文的有界替换视图，不能用作模型历史。最多 32 条近期消息、16 个活动，各文本字段 8192 UTF-8 字节；预算不足可只给标记或完全省略 display，消费者应清除旧视图。pending 仅表示取得 Runtime Ref，placement 当前未知。 |
| `apps/beamlet_agent/lib/beamlet/agent/durable.ex` | `Beamlet.Agent.Durable`：`step`, `position`, `runtime`, `with_runtime`, `persistence`, `open`, `inspect`, `accept_input`, `prepare`, `consume`, `accepted_refs`, `block`, `decide`, `fork`, `restore`, `context`; 类型 `t`, `runtime`, `restored`, `forked` | Agent 拥有的输入、准备与结果引用消费编排，使用 format3 authority。只把已提交事件归约到控制状态；未知写入按命令 ID 读取原响应，不重发写入或业务工作。恢复会提升 generation 并暂停，已声明发送而未解决的尝试不可再次发送。 |
| `apps/beamlet_agent/lib/beamlet/agent/history.ex` | `Beamlet.Agent.History`：`query`, `turns`, `turn_events` | 独立于实时 provider 的只读历史投影。游标保留 Agent 高水位；steps/tools 仅展示该截止位已消费的输出，evidence 单独标记为 Operation 快照。 |
| `apps/beamlet_agent/lib/beamlet/agent/integration/caller.ex` | `Beamlet.Agent.Integration.Caller`：`profile?`, `operation`; 类型 `profile` | 把模型绑定或可移植工具路由转换为有界 Operation。配置版本摘要排除对话、参数和凭证；本地设置与工作区根不进入工具路由。 |
| `apps/beamlet_agent/lib/beamlet/agent/integration/handler.ex` | `Beamlet.Agent.Integration.Handler`：`run` | 执行端适配层，只解析本地安装的可信模型 provider 与工具。重新校验模型请求和 invocation；工具拒绝非空凭证，原生 Context 只收到进度和取消钩子。 |
| `apps/beamlet_agent/lib/beamlet/agent/lifecycle.ex` | `Beamlet.Agent.Lifecycle`：`run` | 隐藏实现保留 false；控制器不直接调用阻塞基础设施；登记/准入 5 秒及总生命周期 65 秒定时器运行在阻塞 worker 之外。 |
| `apps/beamlet_agent/lib/beamlet/agent/loader.ex` | `Beamlet.Agent.Loader`：`load`, `references`, `operation`; 类型 `loaded` | 固定历史高水位的有界重建。校验缓存对应的完整前缀再归约后缀；缓存无效回退历史，历史或引用损坏则阻塞，不修复也不执行。 |
| `apps/beamlet_agent/lib/beamlet/agent/model_binding.ex` | `Beamlet.Agent.ModelBinding`：`registry`, `portable?`, `valid?`, `validate`; 类型 `t`, `placement` | 验证 Agent 固定的模型绑定。父级委派只验证可移植数据；实际创建 authority 解析自身 provider 注册表并验证适配器。credentials 只在运行中传递。 |
| `apps/beamlet_agent/lib/beamlet/agent/operation_owner.ex` | `Beamlet.Agent.OperationOwner`：`run` | 隐藏实现保留 false；阻塞 submit/ack 位于 Lifecycle 的 linked worker，控制器可在基础设施挂起时独立响应所有权丢失。 |
| `apps/beamlet_agent/lib/beamlet/agent/reducer.ex` | `Beamlet.Agent.Reducer`：`version`, `new`, `decisions`, `reduce`, `replay`, `decode` | 持久化事件信封到纯 Core 的适配层。先验证版本、标识与控制载荷，再传递标准化事件；不执行模型或工具，也不写入存储。 |
| `apps/beamlet_agent/lib/beamlet/agent/ref.ex` | `Beamlet.Agent.Ref`：; 类型 `t` | 包含 authority、ID、PID 和 incarnation 的实时身份。基础设施丢失后不重建；持久化读取使用 locator，重新连接必须显式发现当前实例。 |
| `apps/beamlet_agent/lib/beamlet/agent/resources.ex` | `Beamlet.Agent.Resources`：`start_link`, `fence_agent`, `init`, `handle_call`, `handle_info`, `terminate` | 隐藏实现保留 false；资源组额度直到所有成员 DOWN 才释放；persistent_term 仅存 VM 内基础设施 PID 清单，不存业务历史或重放状态。 |
| `apps/beamlet_agent/lib/beamlet/agent/server.ex` | `Beamlet.Agent.Server`：`start_link`, `init`, `handle_call`, `handle_info`; 类型 `state`, `pending`, `owner`, `child_result` | 隐藏实现保留 false；业务终态不等于资源退出：owners/helpers 保留到 Resources 观察整组 DOWN 后，才允许后续调度或 continue。 |
| `apps/beamlet_agent/lib/beamlet/agent/trace_export.ex` | `Beamlet.Agent.TraceExport`：`begin`, `export`, `write`, `verify`; 类型 `fixed` | 有界 format2 离线轨迹。begin 先捕获 Agent 与各 Operation 高水位和引用闭包，再向空目录写入；缺失内容明确列出，不宣称完整。校验不授予导入或执行权限，文件哈希不是签名。 |
| `apps/beamlet_agent/lib/beamlet/agent/trace_snapshot.ex` | `Beamlet.Agent.TraceSnapshot`：`capture`, `valid_evidence`, `valid_operation`; 类型 `t` | 隐藏实现保留 false；写页前捕获固定 Operation 向量与内容闭包；缺失记录显式标记，不能把截断轨迹称为完整。 |
| `apps/beamlet_agent/lib/beamlet/agent/trace_verifier.ex` | `Beamlet.Agent.TraceVerifier`：`closure` | 隐藏实现保留 false；离线校验同时检查归属、来源与内容摘要；重新计算文件哈希本身不足以证明引用一致。 |
| `apps/beamlet_agent/lib/beamlet/agent.ex` | `Beamlet.Agent`：`start`, `start_local`, `list`, `lookup`, `close`, `input`, `delegate`, `peer_request`, `peer_reply`, `peer_take`, `inbox`, `snapshot`, `stop_turn`, `subscribe`, `unsubscribe`, `ack`, `restore`, `fork`, `history`, `export`, `continue`, `command`; 类型 `turn`, `error`, `result`, `command_result`, `locator`, `snapshot`, `child_specification` | 显式 authority 上的有界异步 Agent。AuthoritySupervisor 提供身份与资源监督；模型绑定在实例生命周期内固定，工具通过 Runtime 执行。每实例一次活动 turn，最多 16 个模型步骤、8 个并行工具；完整回复和兄弟批次在发送前验证。不重试不确定执行；持久化恢复只激活为暂停状态，必须显式 continue。 |
| `apps/beamlet_node/lib/beamlet/node/agents.ex` | `Beamlet.Node.Agents`：`discover`, `retain`; 类型 `result` | 对显式可信节点集合聚合最终观察到的 Agent 身份。最多 32 节点、8 并发、一个 5 秒接收预算及完整 1 MiB 信封；complete 仅针对请求集合，失败逐节点列出。初始断连拒绝，预检后 OTP 仍可能重连。 |
| `apps/beamlet_node/lib/beamlet/node/cluster.ex` | `Beamlet.Node.Cluster`：`authority`, `connect`, `connected` | 受信部署名称解析、单次连接与已连接节点过滤。仅 allowlist 内经验证的 ASCII node@host 名称转换为 atom；最多 32 个、每个 255 字节。5 秒等待不代表 OTP 握手立即停止。 |
| `apps/beamlet_node/lib/beamlet/node/observation.ex` | `Beamlet.Node.Observation`：`local`, `local_read`, `observe`, `retain`; 类型 `local_observation`, `services`, `readiness`, `aggregate` | 隐藏实现保留 false；一次性 linked 读取隔离迟到回复；远端预算从执行 VM 的入口开始，调用者放弃不等于远端立即取消。 |
| `apps/beamlet_node/lib/beamlet/node/provider.ex` | `Beamlet.Node.Provider`：`start_link`, `init` | 执行器本地工具设置所有者；WorkspaceRead 启动时检查根与读取上限。Provider 丢失耦合 Runtime 拆除；注册不调用模型网络接口。 |
| `apps/beamlet_node/lib/beamlet/node/routes.ex` | `Beamlet.Node.Routes`：`start_link`, `init`, `handle_call` | 公开可移植工具路由及纯数据 catalogue，独立于执行器设置。仅保留声明角色与公开数据，不复制完整启动配置。 |
| `apps/beamlet_node/lib/beamlet/node/runtime.ex` | `Beamlet.Node.Runtime`：`child_spec`, `start_link` | 隐藏实现保留 false；Provider 先启动，再将其 PID 纳入 Runtime 监控；Provider 丢失后旧执行资源必须拆除。 |
| `apps/beamlet_node/lib/beamlet/node/storage/operator.ex` | `Beamlet.Node.Storage.Operator`：`initialize` | 可信运维者显式安装角色所需数据集。已有数据集拒绝，不覆盖或自动升级；成功后停止自己启动的 Repo，不停止宿主已有资源。多数据集顺序安装并非跨库原子事务。 |
| `apps/beamlet_node/lib/beamlet/node/storage.ex` | `Beamlet.Node.Storage`：`configuration`, `datasets`, `start_link`, `runtime`, `status`, `init`, `handle_call`, `handle_info`, `terminate`; 类型 `datasets`, `configuration`, `wiring` | 宿主显式启动的持久化资源接线，打开已有数据集并管理 Admission；不自动初始化、迁移或修复。拒绝数据集时保留安全原因并关闭持久化准入。runtime 返回句柄不授予准入，每次提交与接受仍咨询实时 gate。 |
| `apps/beamlet_node/lib/beamlet/node.ex` | `Beamlet.Node`：`observation`, `observe`, `profile`, `catalogue`, `start_link`, `init`, `configuration`; 类型 `role`, `profile`, `profiles`, `options` | 由宿主监督树显式启动的可信角色组合，每 VM 一棵树。支持 interaction/authority/executor 的七种非空组合；没有 Application 回调，不读取宿主配置或自动建库。one_for_all 将角色资源故障耦合，重启不重放业务。 |
| `apps/beamlet_node/lib/mix/tasks/beamlet.storage.migrate.ex` | `Mix.Tasks.Beamlet.Storage.Migrate`：`run` | 显式安装 authority 与 journal 的运维命令。--storage 必须是绝对路径的可信 Elixir 文件，该文件会被求值；禁止把它当作不可信上传内容。宿主启动和 Agent 均不隐式调用。 |

## 文档路径与主要契约

- `apps/beamlet_runtime/README_zh.md`：职责/真实依赖、显式共享与执行树、Handler 示例、submit/status/cancel/ack、credits、有限保留、报告容量与本地时钟、持久化 prepare/claim/journal/accept/evidence/no-retry。
- `apps/beamlet_agent/README_zh.md`：显式 authority、固定 binding、上下文与工具批次、资源组实际 DOWN、订阅/展示/发现、委派/peer、创建、只读 inspect、暂停 restore/continue、同 authority 扁平引用 fork、固定 history/export、未知与环境风险。
- `apps/beamlet_node/README_zh.md`：七种角色、实际依赖、本地 deterministic 示例、routes/profile 与 model_providers/providers 区别、可信连接/聚合、观察、独立 Storage host/operator 与安装命令。
- 本交接：`.trellis/tasks/10-19-documentation-zh/research/coverage-orchestration.md`。三个 README 仅链接实际存在文件。未编辑共享 coverage 或其他组件。

重要限制：取消请求不是终止证明；本地 DOWN 不证明外部停止/回滚/停止计费。Result 接受不证明整组资源退休。初始连接预检不能禁止后续 OTP 重连；调用方超时不代表远端立即取消。restore 只激活并暂停，claimed unresolved 不可重发；fork 默认风险未确认，运维 confirmed_stopped 只是断言。丢失历史/引用与未知执行不能靠缓存或重试修复。读取/导出/离线校验不授予执行权，哈希不是签名。

## 语义证据与核对范围

- 完整读取本表 41 个源文件及应用 manifest/既有 README；相关调用链位于本批源码内（Server → Caller/OperationOwner → 公共 Runtime，Durable → Loader/ContextBuilder，Node → Authority/Runtime/Storage）。
- 完整读取基础 `runtime_test.exs`、`agent_test.exs`、`node_test.exs`，以及 Node support binding/fixtures；fork/history_export 测试阅读了与示例及固定高水位对应的前部断言，并运行完整两份文件，未声称逐行审阅两份完整测试。
- 已加载任务/父 PRD、design、implement、curated manifests、lanes、共同覆盖清单、before-dev 和相关 backend 主题规范。

## 实际验证

| 命令/检查 | 结果 |
| --- | --- |
| `mix format`（显式列出本批 41 个 lib .ex） | 通过；未运行全项目格式化 |
| `mix format --check-formatted`（同 41 文件） | 通过 |
| `mix compile --warnings-as-errors` | 通过 |
| `mix test apps/beamlet_agent/test/beamlet/agent_test.exs apps/beamlet_runtime/test/beamlet/runtime_test.exs apps/beamlet_node/test/beamlet/node_test.exs --seed 631927` | Runtime 16 + Agent 4 + Node 5，全通过 |
| `mix test apps/beamlet_agent/test/beamlet/fork_test.exs apps/beamlet_agent/test/beamlet/history_export_test.exs --seed 631927` | 39 项通过，默认 SQLite |
| `elixir scripts/quality/check-contracts-test.exs` | 40 项通过 |
| `elixir scripts/quality/check-contracts.exs` | 148 文件/1345 函数，missing 0、errors 0 |
| 忽略 doc/moduledoc/typedoc 与位置元数据的 AST 比较 | 41/41 相同；基线为本 worker 编辑前的文件副本，而非 HEAD（保护既有工作区） |
| 隐藏文档标记比较 | 41 文件所有 @doc false/@moduledoc false 顺序/数量保持 |
| 三个中文 README 相对链接 | 全部目标存在；示例接口按源码/测试核对，未运行有外部副作用的文档命令 |
| `git diff --check` | 通过（全工作区） |

AST 辅助脚本第一次遗漏 `args=nil` AST 节点的位置元数据，报告行号差异；补齐元数据归一化后 41 文件全通过，没有为此修改生产表达式。日志位于 /tmp/orch-tests.log、/tmp/orch-reference-tests.log、/tmp/orch-contract-tests.log、/tmp/orch-contracts.log；这些临时路径供当前会话复查，本交接保存持久结果。

## 剩余风险及集成门槛

本组件交付无剩余文档缺口或工具阻塞。没有增加业务测试。完整 umbrella tests、Credo、Dialyzer、全局链接/中文基线以及命名 peer/真实 PostgreSQL/部署 gates 未在本批执行，由集成所有者按总计划记录，不能算本批通过；默认 SQLite 39 项不证明 PostgreSQL。本机测试日志的故障注入 gateway_lost 和 OS monitor/磁盘告警未造成失败。未验证物理跨机、付费 provider、断电、恶意 provider 保密；未宣称此类验收。英文新增/双向语言基线继续等待中文验收。

没有修改共享父 coverage.md、verification.md 或任何其他组件。未暂存文件。
