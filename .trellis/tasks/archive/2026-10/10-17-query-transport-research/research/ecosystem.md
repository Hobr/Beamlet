> 来源与范围：恢复自先前研究子代理保存的完整文档 artifact（6dc6bbae）；仅移除子代理 acceptance-report。以下文档/源码抓取快照未重新联网核验，不是第三方库兼容性实测。原文中的“实验待完成”描述该子研究当时的边界；实验现已完成，综合判断以 [report.md](report.md) 和 [experiment-findings.md](experiment-findings.md) 为准。

> 留存状态（2026-10-17）：用户已接受后续 simplify-agent-queries 实现，按约定清理本任务的 results/、experiments/ 及专用 .gitignore。原始记录、失败日志、源快照和实验脚本不再随仓库提供，不能按原命令复现。本文保留历史结论及来源，不冒充仍可读取的原始证据；涉及“当前/现有”的描述均指研究时基线9657d2a。后续实现与验收见[已归档实现任务](../../10-17-simplify-agent-queries/prd.md)。

# Research: OTP / Elixir 只读 live Agent 发现与 lookup

## 摘要

**标准 OTP 并非不可用，也不能把现代 `:rpc.call` 等同于传统 rex 排队协议。** 若接受“客户端超时后，远端只读工作仍可能有限地完成”，最小候选是 `:erpc` 调用 authority 上受限的查询函数，保留本地 Registry 与 PID/incarnation 校验，并把远端业务读取预算、容量限制和查询故障隔离单独做好；异步 `:gen_server.send_request/receive_response` 与 `Task.Supervisor` 可分别解决响应管理和 worker 监督，但不自动组成远端取消协议。

若保留现有“逐消息不自动连接、过期请求不得进入业务读取、调用方丢失后远端有界清理”的严格契约，则需要**authority 侧准入/租约与本地 watchdog**，仅替换成 RPC/Task 不足。现有 Endpoint 是可评估的实现，不是天然优胜者；它与 authority 共属一个库不要求共处 `one_for_all`，当前故障域反而是独立需修正的风险。

### 证据范围

- 只读读取指定任务文档及当前 discovery/authority 源码；未运行应用、安装依赖、测试第三方库或修改项目。以下是**文档/源码证据与研究推论，不是实验结果**。
- 抓取的官方页面标识为 **OTP 29.1.2**（kernel 11.0.4、stdlib 8.1.1、erts 17.1.1）和 **Elixir 1.20.4**；OTP/Elixir 关键源码使用固定 tag。社区 main/master 与 Hex 页面为抓取快照，不能冒充固定发布版源码。
- 不以未经核验的本机日期判定“最近活跃”；下文照录发布/仓库时间字段。搜索索引有旧版本摘要，以抓取的一手页面为准。`source_check` 已用于关键语义/风险核查，但工具只返回段落、自动语义判定不可用；结论由人工阅读原始文档/源码支持。

## Findings / 主要发现

### 1. 现代 rpc、erpc 与 rex 必须分开

**Claim：OTP29 `rpc:call/5` 直接委托 `erpc:call/5`；暂停 rex 不是验证现代 call 阻塞的充分方法。Support：直接源码证据；Confidence：高。**

固定源码 [`rpc.erl@OTP-29.1.2`](https://github.com/erlang/otp/blob/OTP-29.1.2/lib/kernel/src/rpc.erl) 的 `call/5` 明确是 `call(N,M,F,A,T) -> ?RPCIFY(erpc:call(N,M,F,A,T)).`，文件还注明“As of OTP 25 the rpc module require server side support for erpc”。`rpc` 将结果/异常转换成传统 `{badrpc,...}` 形式；若需明确区分结果、远端异常和传输错误，优先 erpc。

同一文件仍保留 rex：`handle_call({call,...})` 派生执行进程，`block_call/5` 经 `do_srv_call` 请求 rex，而 `handle_call({block_call,...})` 在 rex 回调中执行函数。官方 [`rpc:block_call/5`](https://www.erlang.org/doc/apps/kernel/rpc.html#block_call/5) 特别警告它还会阻塞其他操作。因此：传统 rex 探针应明确协议/入口和 trace，不能用 `rpc.call` 名字推断路径，也不应推荐以 `block_call` 查询 Agent。

[`erpc.erl@OTP-29.1.2`](https://github.com/erlang/otp/blob/OTP-29.1.2/lib/kernel/src/erpc.erl) 的 `call/5`、`send_request/4` 使用 `spawn_request(...,[{reply,error_only},monitor])`。本地调用可能优化为直接执行；[`call_options`](https://www.erlang.org/doc/apps/kernel/erpc.html#t:call_options/0) 的 `always_spawn: true`（OTP28 起）可要求新进程，但**不是超时取消或容量上限**。

### 2. 放弃响应 ≠ 撤回请求 ≠ 停止远端工作

**Claim：erpc/gen_server 的 receive_response 超时主要是响应生命周期保证，不是远端执行取消。Support：直接文档与源码；Confidence：高。**

- [`erpc:receive_response/2`](https://www.erlang.org/doc/apps/kernel/erpc.html#receive_response/2)：超时后请求被 abandoned，抛 `{erpc,timeout}`，“no response ... will ever be received after a timeout”。[`call/5`](https://www.erlang.org/doc/apps/kernel/erpc.html#call/5) 对 timeout/noconnection 都说明函数“may or may not be applied”；调用函数自行发送的其他消息仍可能到达。不能把无迟到 RPC 响应解释成无远端残余工作。
- [`gen_server:send_request/2`](https://www.erlang.org/doc/apps/stdlib/gen_server.html#send_request/2) 请求仍由 `handle_call/3` 处理；[`receive_response/2`](https://www.erlang.org/doc/apps/stdlib/gen_server.html#receive_response/2) 在支持 alias 的节点（OTP24+）超时后忽略后续响应；`wait_response/2` 超时则保留继续等候的能力。异步接口有助于不阻塞发起进程、收集多请求和区分错误，但不减少服务器处理这条业务消息的必需工作。
- [`erlang:alias/1`](https://www.erlang.org/doc/apps/erts/erlang.html#alias/1)、[`unalias/1`](https://www.erlang.org/doc/apps/erts/erlang.html#unalias/1) 控制回复地址有效性；不是接收端邮箱删除 API。
- [`spawn_request_abandon/1`](https://www.erlang.org/doc/apps/erts/erlang.html#spawn_request_abandon/1) 原文：“The request is however not withdrawn, so a new process may or may not be created”。若原请求含 link，后续成功创建时会给新进程发 `abandoned` exit；也不等于它绝未启动过。erpc 源码的 `call_abandon/1` 使用 abandon/demonitor，而非远端 kill。

**研究推论：**杀掉查询 helper 只能阻止其后续执行，不能撤回它已经发入 Agent `GenServer` 邮箱的 `:ref` 请求。Server suspend 后恢复，仍可能处理它。现有 Endpoint 的 challenge/租约能约束准入与 helper 寿命，但不应被描述成对任意已发送业务消息的事务性撤回。要保证“过期后连业务读取也绝不开始”，接收业务请求的一侧必须理解并检查有效性/期限；查询层 alone 无法给任意未改造 GenServer 补上此保证。

### 3. Task.Supervisor 适合监督与隔离，不自动给执行加 TTL

**Claim：async_nolink、terminate_child、shutdown 各有边界，网络分区使远端取消无法仅由客户端确认。Support：直接文档/源码；分区结论为研究推论；Confidence：高。**

[`Task.Supervisor.async_nolink/3`](https://hexdocs.pm/elixir/1.20.4/Task.Supervisor.html#async_nolink/3) 不链接调用者，要求 temporary task；任务失败不会通过 link 带崩调用者，调用者仍须处理 `{ref,result}` 与 `:DOWN`。**nolink 也意味着不能假定调用者死后正在执行的任务必然随之退出。** [`Task.Supervised.reply` 固定源码](https://github.com/elixir-lang/elixir/blob/v1.20.4/lib/elixir/lib/task/supervised.ex) 在启动握手期 monitor owner，收到实际 MFA 后先 demonitor，再执行 `invoke_mfa`；启动期 5000ms 超时不是整个任务执行 TTL。

- [`Task.yield/2`](https://hexdocs.pm/elixir/1.20.4/Task.html#yield/2) 只等候；可组合 [`Task.shutdown/2`](https://hexdocs.pm/elixir/1.20.4/Task.html#shutdown/2)：先发 shutdown，超时后 kill，或 `:brutal_kill`。这是停止 **task 进程**，不负责撤销其他 server 消息/外部副作用。
- [`Task.Supervisor.terminate_child/2`](https://hexdocs.pm/elixir/1.20.4/Task.Supervisor.html#terminate_child/2) 通过拥有任务的 supervisor 终止 child。任务 `shutdown:`（默认 5000ms）是**监督树关闭宽限**，不是自动运行期限；文档注明 task 必须 trap exits 才会利用宽限期。可配置 `max_children` 约束并发。
- 远端 task 的启动、monitor、回复、shutdown 都涉及分布式信号。源码专门记录“断线→启动调用失败→迟来的 task link/monitor 使节点重新连接”的竞态，并以启动握手超时避免永久等待；因此它不是严格 no-auto-connect 原语。
- **研究推论：**分区时客户端看到 `:DOWN/:noconnection`，仅知道不可达，不能据此证明远端 task 已死；`terminate_child` 自身也可能送不到远端。要在客户端消失或断线后有界回收，远端本地 watchdog/执行 deadline 才是独立于取消消息的保障。不能仅设调用超时，也不能笼统声称 `async_nolink` 在所有阶段永留任务。

### 4. strict no-auto-connect 是连接策略，不是查询 API 名称

**Claim：默认 erpc/远端 GenServer/Task 不提供逐调用 noconnect 保证；连接预检查存在竞态。Support：官方 API/源码直接证据及推论；Confidence：高。**

[`erlang:send/3`](https://www.erlang.org/doc/apps/erts/erlang.html#send/3) 的 `noconnect` 明确表示若需自动连接则不发送并返回 `noconnect`；`nosuspend` 表示若发送需要挂起则返回 `nosuspend`。erpc 的公开 call options 仅 timeout/always_spawn，其 spawn_request 路径没有每调用 `noconnect` 选项。**先检查 Node.list 再 RPC 不能覆盖检查后断线**。

可选标准配置是 [`kernel dist_auto_connect = never`](https://www.erlang.org/doc/apps/kernel/kernel_app.html)：官方定义“Connections are never automatically established, they must be explicitly connected”。这可用于**整个 VM** 不允许隐式连接的部署，不能与仅查询路径的细粒度契约混为一谈；显式 connect、libcluster 等连接管理器仍需单独限制。它也不处理过期准入/远端取消。

**研究推论：**若不能更改全 VM 连接策略而只要求 discovery 严格不自动连接，需使用 `send(...,[:noconnect,:nosuspend])` 的小协议，并审计请求、challenge、心跳、回复、取消以及远端 monitor/link 等旁路；只改第一跳不够。调试 RPC、远端 monitor、探活也会污染此实验。OTP 文档还警告 distribution 阻塞可能让 erpc timeout 显著延迟，不能把毫秒预算写成硬实时保证。

### 5. 库所有权与故障域应分离

**Claim：当前 Endpoint 异常可能经 one_for_all 连带重启 Agent；这不是 RPC/自定义协议的必然属性。Support：项目只读源码 + 官方监督语义；Confidence：高（实际 PID 变化仍待实验）。**

项目 `apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex:11–32` 将 Registry、Resources、Delegations、Agents 与 Endpoint 作为同一 `one_for_all` 的 children。[Supervisor strategies](https://hexdocs.pm/elixir/1.20.4/Supervisor.html#module-strategies) 规定：需重启的 child 终止时其他 children 被终止后一起重启。因此“查询属于 agent 库，所以必须跟 authority 共生死”没有依据。

**研究建议（不是已实施设计）：**保留身份岛内部 Registry/Agent 的生命周期语义，把可失败查询层放在独立监督子树/兄弟 one_for_one 域；对端点/TaskSupervisor 重启强度耗尽向上升级的风险仍需审查。查询仅 monitor authority，不 link Agent；Registry 不可用时 fail closed，重连后重新验证 PID/incarnation，不能用旧 ID 重新绑定新 Agent。标准 RPC 不会自动修复现有 Endpoint 所在监督树，换协议也不是替代故障域设计。

## 方案比较

| 候选 | 范围、身份一致性 | 失败/清理与连接行为 | 成本与本任务适配 |
|---|---|---|---|
| `erpc`（`rpc.call` 为兼容包装） | authority 上执行白名单只读函数；本地 Registry 仍权威 | 超时放弃响应，不保证取消；默认可建连；须远端预算/有界读取 | 无新增依赖，**允许有限后台完成时首选候选**；不必排除 RPC |
| `gen_server.send_request/receive_response` + alias | 已知 Endpoint/Server 的请求响应；不提供跨节点目录 | alias 清理迟回复，不撤回队列；远端调用无逐请求 noconnect 公开选项 | 标准构件；适合非阻塞等待/多请求收集，不是完整取消协议 |
| 本地 `Task.Supervisor` + temporary worker/watchdog | 单次执行监督，与 Registry 身份无关 | nolink 隔离调用者；shutdown/terminate_child 可终止 worker；TTL/owner-loss 需另做；远端版本受分区限制 | 中低复杂度；远端 watchdog 本地执行优于依赖跨分区 kill |
| 当前自定义 Endpoint | offer/confirm、fresh challenge、lease、容量/结果限制；查询本地 Registry | 全路径 send_safe 使用 noconnect/nosuspend；worker 到期清理；**已入 Agent 邮箱消息不能因此撤销**；当前 one_for_all 有耦合 | 无第三方依赖但协议状态机/竞态成本高；严格契约下有理由保留评估，不应先验判更好 |
| **gen_rpc** | 替代传输：独立 TCP/SSL、按节点/键分片；不是注册表 | 文档有 connect/send/receive/inactivity 超时、async 结果持有进程超时；缺少可据以承诺远端任务取消/过期准入的证据；会按需建自己的连接 | 多端口、配置、协议与运维负担；没有现代 erpc 性能瓶颈实测时不为低频 discovery 引入 |
| **Syn** | scope 化全局注册/组管理，strong eventual consistency | 复制/冲突恢复有常驻成本；**默认冲突策略会向 loser 发 exit**，可定制回调避免；不是 worker 取消器 | 可以作非权威候选索引；不能无条件替换本地 Registry，否则扩大身份与终止语义 |
| **Horde** | CRDT registry + distributed supervisor，最终一致 | registry 冲突向 loser 发 exit；supervisor 可在不可达时重分布进程；不解决只读请求 TTL/no-connect | 对现有固定 authority/incarnation 模型过重，可能主动改变业务生命周期；不推荐为查询引入 |
| **libcluster** | 拓扑发现/自动集群形成，不做 Agent lookup | 默认 `net_kernel:connect_node`；自动形成/恢复连接与“任何组件绝不自动建连”冲突 | 如部署本来需要组网可单独选型；不是查询协议/注册表/取消方案 |

### 社区候选的直接证据与发布/维护快照

以下版本**都未在 OTP29 / Elixir1.20 上安装或实测**。CI 配置只证明声明测试矩阵，不证明本次测试成功；最低版本要求也不等于最高版本兼容认证。

| 项目 | 已抓取发布信息 | 一手维护/兼容证据与限制 |
|---|---|---|
| gen_rpc | [Hex](https://hex.pm/packages/gen_rpc)：2.1.0；Last Updated **2016-10-07**；[GitHub latest release API](https://api.github.com/repos/priestjim/gen_rpc/releases/latest)：2.0.0，published_at **2016-10-04** | [仓库 API](https://api.github.com/repos/priestjim/gen_rpc)：archived=false，pushed_at **2025-11-05**；不能据 Hex 陈旧就断言整个仓库停更，也不能把 branch 当 2.1.0。[README](https://github.com/priestjim/gen_rpc/blob/master/README.md#build-dependencies) 声明 OTP≥19.1；抓到的 [.travis.yml](https://github.com/priestjim/gen_rpc/blob/master/.travis.yml) 仅19.1/19.2，不构成 OTP29 证据 |
| Syn | [Hex](https://hex.pm/packages/syn)：**3.4.2**；Last Updated **2026-06-22**；HexDocs 也标3.4.2 | [仓库 API](https://api.github.com/repos/ostinelli/syn)：archived=false，pushed_at **2026-10-13**；[CI](https://github.com/ostinelli/syn/blob/master/.github/workflows/ci.yml) OTP27/28，没有29；Erlang 库也未据此验证 Elixir1.20 集成 |
| Horde | [Hex](https://hex.pm/packages/horde)：**0.10.0**；Last Updated **2025-11-03** | [仓库 API](https://api.github.com/repos/elixir-horde/horde)：archived=false，pushed_at **2026-10-05**；[CI](https://github.com/elixir-horde/horde/blob/main/.github/workflows/ci.yml) 最高 Elixir1.17 / OTP27；原 derekkraan URL 已解析到 elixir-horde；未见本次所需版本覆盖 |
| libcluster | [Hex](https://hex.pm/packages/libcluster)：**3.5.0**；Last Updated **2025-01-09** | [仓库 API](https://api.github.com/repos/bitwalker/libcluster)：archived=false，pushed_at **2025-01-09**；[CI](https://github.com/bitwalker/libcluster/blob/main/.github/workflows/elixir.yml) 含1.13/22与1.17/27，无29/1.20 |

**gen_rpc（Support：直接文档；Confidence：高；适配判断为研究推论）：**[README Architecture / settings](https://github.com/priestjim/gen_rpc/blob/master/README.md#architecture) 描述按需启动 client 并连接远端，接收端 spawn 执行器；`async_call_inactivity_timeout` 是持有结果进程的卫生机制，不是远端函数运行期限；`call_receive_timeout` 不是取消证明。其“rpc 经单一 rex 瓶颈”和 OTP19.1 生产吞吐叙述是历史背景，**不能用作相对 OTP29 erpc 的现行 benchmark**，本报告不采纳吞吐数字作推荐依据。

**Syn（Support：直接文档/源码；Confidence：高）：**[README Notes](https://github.com/ostinelli/syn/blob/master/README.md#notes) 明确选择 Availability 而非 Consistency；[`syn:lookup/2`](https://hexdocs.pm/syn/3.4.2/syn.html#lookup/2) 返回映射，不证明业务进程当前可响应。[`syn_event_handler:resolve_registry_conflict/4`](https://hexdocs.pm/syn/3.4.2/syn_event_handler.html#c:resolve_registry_conflict/4) 与[源码](https://github.com/ostinelli/syn/blob/master/src/syn_event_handler.erl) 明确默认保留较新注册、向另一 PID 发送 `exit(Pid,{syn_resolve_kill,Name,Meta})`；该 exit reason 不是不可捕获的原子 `kill`，但足以打破“目录只是无影响读侧”的假设。自定义回调可不杀 loser，仍需处理冲突一致性。

**Horde（Support：直接文档；Confidence：高）：**[`Horde.Registry.register/3`](https://hexdocs.pm/horde/0.10.0/Horde.Registry.html#register/3) 说明并发注册可能双方均成功，之后 loser 收到 `{:name_conflict,...}` exit；netsplit 恢复也可触发。[README Fault tolerance/CAP](https://github.com/elixir-horde/horde/blob/main/README.md#fault-tolerance) 说明不可达后重新分配、可能存在重复进程。这是分布式业务所有权方案，不是透明只读 lookup 加速器。

**libcluster（Support：直接文档；Confidence：高）：**[README 配置示例](https://github.com/bitwalker/libcluster/blob/main/README.md#example-configuration) 明确默认 connect 为 `{:net_kernel,:connect_node,[]}`；自动组网/恢复是其目的，不能误报为请求级 no-auto-connect。

## 最小推荐与严格契约替代

### A. 接受有限后台只读完成：优先验证标准 OTP 组合

1. 本地 [Registry](https://hexdocs.pm/elixir/1.20.4/Registry.html) 继续作为 authority 的身份源；list 只枚举安全 descriptor，不读取凭据；lookup 在 authority 本地校验 id、预期 PID，并返回/验证 incarnation。任何结果都是时点观察，重新附着时仍须再次校验。
2. 用 `erpc:call`（或 send_request/receive_response 集合）执行有限、白名单化的查询包装函数；限制输入/结果大小和并发。不以“只读”承诺零 CPU/邮箱影响。`rpc.call` 也能用，但 erpc 错误模型更清楚。
3. 远端对 `GenServer.call(:ref, budget)` 使用**远端自己的有限预算**，避免任何 infinity。绝不能以客户端 `erpc timeout` 代替它。若查询包含不受控阻塞或需要不依赖函数合作的 helper 寿命上界，用独立远端本地 watchdog + temporary worker；TaskSupervisor 提供监督/容量，不独自提供 deadline。
4. 将查询监督域与 Agent 身份岛隔离；不把查询 worker 与 Agent link。若允许已连节点上的断线重连，写清该语义；若整个 VM 可禁隐式连接，评估 `dist_auto_connect=never`，不需要为此立即引入新传输。

**限制：**超时后可能已开始/稍后开始远端包装函数；远端预算从实际开始计算，不能证明“客户端截止后零工作”；helper 退出后 Agent 队列中的只读请求仍可能完成。此方案需要明确批准放宽现有严格契约，而不是把弱保证包装成等价替换。

### B. 保持现有严格契约：小型标准 OTP 协议构件 + 远端准入

沿用/精简 Endpoint 的必要语义：全路径 `send/3 noconnect/nosuspend`、alias 回复、容量限制、authority-local deadline、执行前新鲜 challenge、本地 watchdog/租约、temporary worker；不要依赖分区期间的远端取消 ACK。当前 offer/confirm 之后还有 fresh challenge，不能以旧两阶段实现评判它。跨节点不能直接比较 monotonic timestamp；用本地时钟和往返预算约束。

**仍有限制：**租约意味着“到期后有界停止”，不是瞬时感知调用方死亡；BEAM 调度/阻塞信号不是硬实时；已入业务邮箱消息不撤回。若要求连这类消息都不能在过期后执行，必须让业务接收端也实施准入判断，范围会超出纯传输替换。现 Endpoint 的普通端点异常影响 Agent 的问题必须单独评估监督树，不应靠协议复杂度掩盖。

## Contradictions / 矛盾与易误读点

- gen_rpc README 的 rex 瓶颈论与 OTP29 `rpc:call/5 -> erpc:call/5` 不对应；属于历史机制差异，不是证明 gen_rpc 无用，也不是证明现代 RPC 不可用。
- 搜索摘要称 Syn3.4.1；抓取 Hex/HexDocs/README 为3.4.2。Horde README 安装示例仍为0.8.5，而 Hex/HexDocs 为0.10.0；版本判断采用发布页，不照抄旧示例。
- gen_rpc GitHub latest Release 为2.0.0、Hex为2.1.0、仓库 push 更晚，三者不是同一指标；既不宣称“已弃用”，也不宣称“有 OTP29 支持”。
- “abandon response”“terminate helper”“撤销已排队业务消息”“阻止过期准入”是四件事；任何单一 timeout 返回值都不能同时证明它们。

## Missing evidence / 残余风险

- 本子任务未运行隔离实验，无法报告 rex suspend、调用方死亡、启动/回复期断线、预检查竞态、实际 worker 清理或 PID/incarnation 变化；由主任务实验交付。
- 未安装社区库；没有 OTP29/Elixir1.20 兼容实测，也未把 CI 配置等同于测试通过。Hex API 域名解析失败，但普通 Hex 发布页面及 GitHub 元数据可抓取；没有伪造 API 数据。
- 社区 main/master 源码可能不同于 Hex 包；若进入实施，应固定 tag/commit 再检查 API/冲突策略。没有为“活跃维护”定义或验证 SLA，不从星数/下载量推断质量。
- strict no-connect 必须覆盖所有信号与部署连接管理器；`dist_auto_connect=never` 的全 VM 影响、已有业务显式连接行为尚未评估。
- 本地只读发现同样有 TOCTOU；分布式 registry 的最终一致副本不自动保证当前 authority、存活、incarnation 或重新附着授权。

## Sources / 来源取舍

- **保留：**固定 OTP29.1.2 `rpc.erl`/`erpc.erl`、OTP29 erpc/gen_server/erlang/kernel 文档、Elixir1.20.4 Task/TaskSupervisor/Supervisor 文档与 Task.Supervised 源码——区分响应、执行、监督和连接语义的直接依据。
- **保留：**gen_rpc/Syn/Horde/libcluster 官方 README、Hex 发布页、GitHub API、CI、Syn 冲突源码、Horde.Registry 文档——范围、发布快照与潜在业务终止风险的一手证据，链接已随结论给出。
- **保留：**任务 current-evidence 与当前 authority/discovery 源码——项目约束和故障域的只读证据，不当作实测。
- **降级/不采用：**搜索摘要旧版本、OTP26/27 文档副本、旧 Horde 安装示例、gen_rpc OTP19.1 历史吞吐——不是当前版本兼容或性能比较证据；没有引入 SEO 文章作结论依据。

## Next steps / 最有价值的后续

主任务应先用固定 OTP29.1.2/Elixir1.20.4 的隔离节点，比较 A 方案和当前 Endpoint 的**调用返回、远端 worker、业务邮箱恢复后执行、Agent 身份、连接事件**五条独立观测轴；再决定是否批准放宽严格契约。优先证实监督树失败隔离与断线后远端有界清理，不为本轮选型先安装社区库。
