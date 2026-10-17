# 只读 Agent 查询传输：实验与生态综合报告

> 留存状态（2026-10-17）：用户已接受后续 simplify-agent-queries 实现，按约定清理本任务的 results/、experiments/ 及专用 .gitignore。原始记录、失败日志、源快照和实验脚本不再随仓库提供，不能按原命令复现。本文保留历史结论及来源，不冒充仍可读取的原始证据；涉及“当前/现有”的描述均指研究时基线9657d2a。后续实现与验收见[已归档实现任务](../../10-17-simplify-agent-queries/prd.md)。

## 1. 执行结论

**不应再以“RPC 都经 rex 排队、超时必泄漏”为由排除标准 OTP；也不能把 erpc 直接视为现 Endpoint 的等价替换。**
本机 OTP29 的 `rpc.call/5` 实际委托 erpc。客户端超时/死亡后，有限只读远端函数仍会完成；这是可明确接受的语义，不必自动定义成泄漏。
但默认 erpc 会自动建连，不能阻止过期请求未来才开始，也不提供调用方死亡时的即时取消。

建议分两条、由用户选择契约，**本任务不授权也不实施任何产品迁移**：

- **允许有限后台只读完成**：首选后续验证无新增依赖的 `:erpc` + authority 本地受限查询函数。
  保留 Registry/PID/incarnation 校验、输入/输出/并发上限、远端自己的有限读取预算；必要时用本地 watchdog 管临时 worker。
  若不接受默认隐式连接，须另外评估全 VM `dist_auto_connect=never` 的部署影响，不能以 Node.list 预检查替代。
- **保留现有严格契约**（查询逐消息不自动连接、过期准入防护、caller 失联后有界清理）：继续评估现 Endpoint 所需的
  noconnect/nosuspend、alias、新鲜 challenge、远端本地 deadline/lease 等机制；普通 RPC/Task 不能无条件替代这些语义。
  “严格”也不等于瞬时远端死亡感知或已入业务邮箱消息的撤回；若要求后者，业务接收端也须参与期限判断，需另立范围。
- **独立于传输选型，优先审查查询故障域**：当前 Endpoint 被真正 kill 时会经内层 one_for_all 杀死现有 Agent。
  查询属于 Agent 库不意味着必须同故障域。可研究将查询层置于独立监督子树/兄弟域，但重启强度向上升级仍须设计和验证。
- **不为本次低频 live lookup 引入社区库**：gen_rpc 没有解决严格取消/过期准入的证据；Syn/Horde 改变目录一致性乃至业务生命周期，
  libcluster 是组网而非查询协议。没有现代 erpc 的生产性能瓶颈证据支持增加依赖。

## 2. 证据范围与可信度

| 标签 | 含义与边界 |
| --- | --- |
| 本地观察 | 真正命名 VM、实际 worker/PID/队列/连接事件；本机、有限样本，不升级为跨版本或跨物理机定理 |
| 文档/源码保证 | OTP/Elixir 固定版本源码及官方 API 语义；社区资料为先前抓取快照，不是本次安装测试 |
| 推论/建议 | 基于两类证据的机制取舍与未来设计，不表示产品已实现或用户已同意放宽契约 |
| 未验证 | 明确列在第8节，不能以空日志、CI 声明或“调用返回了”代替实际证明 |

基线 `9657d2a`，核查日期 2026-10-17。最终实验 **`20261017T122252-5c3d06fc`：98 scenarios、98 peer cleanups、run_complete=passed**。
每个关键组合3次独立新 peer，另有1个控制场景和1个96次查询批次。原始记录共205行；不是98项 ExUnit 测试。
原始 JSONL（历史证据，原件已清理）、派生索引（历史证据，原件已清理）、
[详细实验解释](experiment-findings.md)、[OTP 路径](otp-paths.md)、[完整生态研究](ecosystem.md) 保留历史结论；原始/派生记录现已清理。

**独立质量检查 PASS（研究交付，不是产品迁移批准）**：唯一一次full复跑 `20261017T124152-6fd7b540`，
205行、98场景/98清理、final passed，实验进程退出0（125814ms），编译退出0；与原run无连接分类差异。
独立raw（历史证据，原件已清理）、新派生索引（历史证据，原件已清理）、
[review与AC映射](quality-review.md)、验证命令/退出码（历史证据，原件已清理）曾分别保存且未覆盖；本次按用户要求统一清理原件。
121ms本地超时、300ms Endpoint回收、5000–5001ms Endpoint预算均再次观察到；这些仍不是硬实时承诺。

## 3. 环境、执行路径与一手锚点

运行时 **OTP29.1.2 / ERTS17.1.1 / Elixir1.20.4（编译目标 OTP29）**，由运行记录和 OTP_VERSION 双重确认。
本机源码根：`/nix/store/cv5n8x0z3hzaxxdq9zi2mn9aznck46v4-erlang-29.1.2/lib/erlang`。

| 本机源码相对根路径 | 路径事实 / 官方固定版本来源 |
| --- | --- |
| `lib/kernel-11.0.4/src/rpc.erl:492-493` | `rpc.call/5 -> erpc.call/5`，rpc 再映射兼容错误；[OTP-29.1.2 rpc](https://github.com/erlang/otp/blob/OTP-29.1.2/lib/kernel/src/rpc.erl) |
| 同文件 `173-199, 299-303, 531-535` | rex `{call,...}` 派生 worker 后回复；block_call 仍经 rex，**本任务没有运行 block_call** |
| `lib/kernel-11.0.4/src/erpc.erl:297-313, 1352-1356` | spawn_request/monitor；超时 abandon/demonitor，不是远端 kill；[OTP-29.1.2 erpc](https://github.com/erlang/otp/blob/OTP-29.1.2/lib/kernel/src/erpc.erl) |
| 同文件 `243-260` | timeout/noconnection 时函数可能执行，调用方不再得知对应结果；用户函数自己发的消息另论 |
| `lib/stdlib-8.1.1/src/gen.erl:240-279, 317-319` | alias 响应过滤、monitor 与发送路径；[固定版本 gen](https://github.com/erlang/otp/blob/OTP-29.1.2/lib/stdlib/src/gen.erl) |
| `lib/stdlib-8.1.1/src/gen_server.erl:1328-1417, 1500-1533` | 异步请求/响应接口，wait 与 receive 的放弃语义不同；[固定版本 gen_server](https://github.com/erlang/otp/blob/OTP-29.1.2/lib/stdlib/src/gen_server.erl) |

rpc SHA256：`e62d0420294e320fa9185c43a9dff1f8b14438704a78386341a149d2a4896fe8`。
erpc SHA256：`7e5615627bb94221eb9371046cda801922711672c09ceca21b4b2bf19f3572db`；恢复阶段重新读取本机文件核对一致。
现代 rpc/erpc 在 rex 暂停时仍能完成 list/lookup，各3次，是源码路径的实验对照。
真正 rex 场景用 `GenServer.call({:rex, node}, {:call, Fixture, fun, args, :user}, timeout)`，暂停时采到实际 `$gen_call`。
这是 **OTP29.1.2 内部协议探针**，入口强制检查版本；不推荐作公共产品 API，也不把它冒充现代 rpc。

## 4. 实验结果表（本地观察）

RPC三组分别指 rpc、erpc、rex_internal，每组每场景3次；表中毫秒是局部测量，不跨 VM 相减。
完整预期、每次 elapsed、worker DOWN、Agent ref、连接/邮箱样本在原始 JSONL；下表压缩展示，非性能 benchmark。

| scenario 前缀 / 数量 | 控制与耗时 | worker / 队列 / 回复观察 | Agent / 连接观察 |
| --- | --- | --- | --- |
| control_smoke / 1 | 强制断线后 standard_io 控制 | 控制通道仍可读远端；正向显式 connect 成功 | Agent 活；控制读取未建连 |
| normal/{transport} / 9 | list/lookup；现代两组暂停 rex | 都返回真实 fixture PID/incarnation | 无身份替换；不经 rex 排队的现代对照成立 |
| slow_timeout/{transport} / 9 | caller120ms、远端650ms；本地121ms返回 | 返回时远端活，约651ms complete+DOWN；caller 晚邮箱空 | 普通查询失败不杀 Agent |
| caller_death/{transport} / 9 | start 屏障后 kill caller | caller 已 DOWN，远端仍活，约901ms complete+DOWN | Agent 活；不是 caller death 自动取消 |
| suspended_server/{transport} / 9 | Server 暂停；120ms vs 650ms预算 | 121ms本地结束，远端随后DOWN；`:ref`仍排队；恢复后晚邮箱空 | 后续 lookup 同 Ref；Agent活 |
| initially_disconnected/{transport} / 9 | 完全断开才调用，2–4ms调用 | 查询成功 | 三类默认均重连（nodeup） |
| precheck_disconnect/{transport} / 9 | 连通预检查确认→断开→放行调用 | 查询成功，屏障固定先后 | 三类均重连；预检查不是原子连接策略 |
| disconnect_execution/{transport} / 9 | start后断线，900ms自然完成；本地约6ms失败 | 远端仍 complete+DOWN，晚邮箱空 | Agent活；现代两组窗口无重连，rex探针有重连 |
| disconnect_reply/{transport} / 9 | 确认断线后经 standard_io 放行返回 | 本地约6ms失败，远端DOWN，晚邮箱空 | Agent活；现代两组无回复重连，rex探针有重连 |
| endpoint_normal / 3 | 原API、原5秒预算 | 真实ref；active/mailbox归零 | 原Agent身份不变 |
| endpoint_execution_disconnect / 3 | 已入队`:ref`再断线，Server不恢复 | controller/worker均约300ms死；`:ref`仍在 | Agent活；另200ms观察窗无重连 |
| rex_queue / 3 | 暂停rex至caller121ms超时，再恢复 | 超时前无worker；恢复后才start，约201ms完成/DOWN；晚邮箱空 | 证明排队工作可以过期后启动 |
| endpoint_timeout / 3 | 真实Server暂停，保持原5秒预算 | 5000–5001ms返回timeout；两级helper真死；`:ref`仍在；恢复后晚邮箱空 | Agent活 |
| endpoint_caller_death / 3 | 入队屏障后kill caller，不恢复Server | 实际controller/worker约300ms死；不撤回`:ref` | Agent活；是有限lease清理，不是即时取消 |
| explicit_remote_worker_kill / 3 | caller死后，经控制面明确kill远端 | 原先worker仍活，kill后DOWN(reason=killed)；`:ref`仍在 | Agent活；非自动取消协议 |
| endpoint_connections / 3 | 已断线public查询、precheck/send_safe屏障、排队offer回复 | public=unavailable；原语=noconnect；被动offer恢复无active | 三组观察窗无nodeup；不是public私有指令级冻结 |
| endpoint_actual_kill / 3 | 对现Endpoint真正 `Process.exit(pid,:kill)` | 内层Registry/Resources/Agents/Endpoint换PID；旧Agent死；lookup=not_found | 显式重建后新PID/incarnation；outer Node及AuthoritySupervisor PID未变 |
| modest_repeated_concurrent / 1批 | 4传输×24次，concurrency4，批次约1420ms | 全成功；148个traced本地descendants死；active/mailbox/rex monitors均0 | caller/coordinator邮箱空；远端进程126→125，本地120→119 |

迟到邮箱是在本地调用返回后等待1000ms再单次采样，不是从远端完成/Server恢复重新计满1秒；650ms预算组通常仅覆盖恢复后约470ms。
无迟到响应不证明远端没执行、不证明无限未来无消息，更不等于没有重连。

共98个独立peer场景；96个批次调用不是额外96个peer。结束后coordinator连接集为空，最终邮箱保留1条peer停机的nodedown通知，
不要把“批次采样邮箱空”写成“整个退出阶段所有邮箱永远空”。普通查询失败/客户端死亡与端点崩溃是不同故障。
`endpoint_actual_kill/1` 的旧Agent `#PID<26703.183.0>` 确认死亡，显式重建为 `#PID<26703.205.0>` 且 incarnation 改变；
详见[原始前后PID表](experiment-findings.md)。不是 terminate_child/受控重启，也不是证明Agent会自动重建。

## 5. 如何解读：四条互不替代的语义轴

1. **放弃响应**：erpc/alias 在超时后清理对应回复通道；官方 [erpc.call](https://www.erlang.org/doc/apps/kernel/erpc.html#call/5)
   与 [receive_response](https://www.erlang.org/doc/apps/kernel/erpc.html#receive_response/2) 的保证不等于取消执行。
2. **停止worker**：有限远端函数自行完成，或 Endpoint 租约/watchdog 杀helper，或显式kill；是三种不同机制。
   [spawn_request_abandon](https://www.erlang.org/doc/apps/erts/erlang.html#spawn_request_abandon/1) 明说请求没有撤回，进程仍可能被创建。
3. **撤回已入队业务消息**：本轮即使真实worker已死，Agent邮箱仍留 `$gen_call :ref`；恢复仍可处理这条只读消息。
   [alias/unalias](https://www.erlang.org/doc/apps/erts/erlang.html#alias/1) 不是远端邮箱删除API。
   Endpoint的新鲜准入可阻止失效确认启动新worker，不等于让已投递到另一个Server的消息自动失效。
4. **连接与故障域**：[send/3 noconnect/nosuspend](https://www.erlang.org/doc/apps/erts/erlang.html#send/3) 是逐发送策略，
   不等于全VM绝不出现重连；[kernel dist_auto_connect](https://www.erlang.org/doc/apps/kernel/kernel_app.html) 是不同粒度的配置。
   one_for_all 连带重启符合 [Supervisor语义](https://hexdocs.pm/elixir/1.20.4/Supervisor.html#module-strategies)，不由传输名字决定。

由此推论：若“低扰动”容许有界后台只读完成，标准 OTP 可作为最小候选；若要求严格准入/逐消息无自动连接，协议仍有必要。
两者都不承诺零CPU/消息成本、事务性撤回或分布式硬实时。`Task.Supervisor.async_nolink` 解决监督/失败隔离，
[Task.shutdown](https://hexdocs.pm/elixir/1.20.4/Task.html#shutdown/2) 解决停止task；shutdown宽限和启动握手超时不是执行TTL。
远端必须有自己能执行的预算/看门狗，不能靠分区时必达的取消ACK；这些组合没有在本任务另造产品实现实测。

## 6. 生态对比（文档/源码快照，不是兼容实测）

下表发布与CI信息来自恢复的[完整生态报告](ecosystem.md)，未在恢复阶段重复联网抓取；固定tag与main/master证据分开。

| 候选 / 来源 | 可解决什么 | 本任务不选它替代现协议的原因 / 版本证据 |
| --- | --- | --- |
| [OTP erpc](https://github.com/erlang/otp/blob/OTP-29.1.2/lib/kernel/src/erpc.erl) | 明确远端调用错误/响应关联，无新依赖 | 默认重连、不取消；本地29.1.2已实测call，异步组合未单测 |
| [gen_server异步请求](https://www.erlang.org/doc/apps/stdlib/gen_server.html#send_request/2)、[Task.Supervisor](https://hexdocs.pm/elixir/1.20.4/Task.Supervisor.html) | 非阻塞收集、alias、临时task监督/容量 | 各自是构件；monitor/远端启动可能连接；需独立本地deadline；候选组合未实测 |
| 当前 Endpoint | 新鲜准入、有界helper、逐消息noconnect，保留authority身份模型 | 无新依赖但状态机成本高；已测helper死不撤消息、端点崩溃连带Agent死 |
| [gen_rpc README](https://github.com/priestjim/gen_rpc/blob/master/README.md)、[Hex](https://hex.pm/packages/gen_rpc) | 独立TCP/SSL替代传输/分片 | 按需建自己的连接；接收/结果持有超时不是远端取消证据；历史rex性能叙述不适用于OTP29；Hex2.1.0(2016)，仓库push2025，不能简单断言弃用；CI19.1/19.2非29 |
| [Syn 3.4.2](https://hexdocs.pm/syn/3.4.2/syn.html)、[冲突回调](https://hexdocs.pm/syn/3.4.2/syn_event_handler.html#c:resolve_registry_conflict/4) | scope化分布式注册/组、强最终一致 | 默认向冲突loser发exit，可自定义；不是透明无影响查询层，不替代权威PID/incarnation校验；发布2026-06-22，CI27/28非29 |
| [Horde 0.10.0 Registry](https://hexdocs.pm/horde/0.10.0/Horde.Registry.html#register/3)、[README](https://github.com/elixir-horde/horde/blob/main/README.md) | CRDT目录与分布式监督/重分布 | 冲突exit、分区后可能重复/迁移进程，改变固定authority业务生命周期；发布2025-11-03，CI最高Elixir1.17/OTP27 |
| [libcluster](https://github.com/bitwalker/libcluster/blob/main/README.md)、[Hex](https://hex.pm/packages/libcluster) | 集群拓扑/自动连接管理 | 默认connect_node，不是lookup/取消协议；3.5.0(2025-01-09)，CI最高1.17/27 |

四个社区候选均**未安装、未在OTP29/Elixir1.20兼容实测**；仓库未归档/CI矩阵/最低版本不是本次通过证明。
Syn/Horde默认冲突exit的具体reason并非都不可捕获kill，也不能因此将其目录视为纯读无影响。
本地Registry继续是authority身份源；分布式副本最多作候选索引，附着前仍须当前PID/incarnation校验，不能按旧ID默默重建。

## 7. 历史验证与清理后的可追溯范围

2026-10-17，用户明确接受后续实现，触发已约定清理。原实验入口、原始JSONL、派生索引、失败日志、源快照和清理审计已删除，原复现命令不再提供。两轮run ID、运行时、98场景/98清理、独立PASS与限制由本文及quality-review.md留存；它们是历史摘要，不能替代逐条原始数据或宣称目前仍可复核原始记录。

历史launcher使用私有epmd、standard_io控制、低scheduler、随机cookie和有限进程组watchdog；不接触生产集群。原既有Discovery测试曾9 passed/seed631927，这与98场景及96次批次调用分开计数，不表示新实现测试。
全局result*忽略曾妨碍证据持久化，任务专用例外在研究交付时生效；本次随目录一并删除，不改root或全局忽略规则。

产品已在后续任务迁移为有限local/erpc读取；当前产品验收使用apps下的长期回归，详见[新实现验收](../../10-17-simplify-agent-queries/acceptance.md)和[验证报告](../../10-17-simplify-agent-queries/verification.md)，不依赖本研究的已删目录。

## 8. 失败、恢复及未验证项

早期 smoke缺Elixir启动、full的improper alias JSON编码失败均有独立日志；另两次precheck/send_safe失败如实保留。
其中一次保存 `send_safe=ok` 后出现nodeup，旧run未trace确切发送者，**不能声称已证明其根因**。
源码显示rex observer的feature_request/reply使用普通发送，可扰动快速断连；最终增加交换完成屏障/本VMtrace，所得无重连仅限观察窗。
此前工作流 `6dc6bbae` 最终交接超时，实验子进程 `30801c5f` 据恢复派发已terminal；这是编排交接中断，不是最终实验超时失败。
恢复阶段读取现存证据、还原生态artifact并完成本报告；当时没有重跑或独立复核。本轮独立review随后真实复跑一次full并审核证据，结果见第2节及 quality-review.md；不将新验证归到历史恢复阶段。

未验证：多物理机/生产部署、网络丢包/半开、长期压力/生产性能、第三方兼容、全仓静态分析/LSP，
`dist_auto_connect=never`部署影响、outer重启强度耗尽、public-query私有指令级竞态、瞬时分布式取消/业务队列撤回。
同机三次重复是有界故障证据，不证明所有调度/网络状态；任意不合作函数不能仅靠调用方超时得到远端时限。

## 9. 验收映射与后续门禁

| AC / 需求 | 可核对证据 | 当前结论 |
| --- | --- | --- |
| AC1 / R1 | runtime行、源码哈希/固定tag、rex真实mailbox、复现入口 | 已有客观证据；内部探针版本锁定 |
| AC2 / R2 | 第4节覆盖98场景，raw每条expected/elapsed/worker/connection/reply，关键组各3轮 | 已有客观证据；未测网络状态明确列出 |
| AC3 / R3 | 普通超时/caller death Agent活，对照endpoint_actual_kill前后PID/incarnation；第1/5节隔离建议 | 已区分真实故障域；隔离修改未实施 |
| AC4 / R4 | 第6节及ecosystem官方文档/源码/发布/CI来源，四候选适用性 | 文档研究完成，不冒充兼容实测 |
| AC5 / R5 | experiments、raw/失败日志、源快照、来源、两条最小推荐及限制 | 研究交付完成；非产品迁移批准 |
| AC6 / R6 | 98 cleanups、原审计/恢复审计、产品无diff/无stage、任务内results例外 | 研究范围/清理有证据；不触及共享进程 |

PRD框表示上述研究证据已交付；本轮独立review已核验观察防污染、结果持久化与AC，结论PASS，详见 [quality-review.md](quality-review.md)。
上述为研究交付时结论。用户随后批准有限后台完成语义，后续实现已验收通过；本任务历史结论不作为新产品验证证据。任务状态未自动修改或归档，未提交。
