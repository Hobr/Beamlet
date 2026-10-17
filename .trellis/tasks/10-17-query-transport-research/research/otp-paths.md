# 本机 OTP 查询执行路径核查

> 留存状态（2026-10-17）：用户已接受后续 simplify-agent-queries 实现，按约定清理本任务的 results/、experiments/ 及专用 .gitignore。原始记录、失败日志、源快照和实验脚本不再随仓库提供，不能按原命令复现。本文保留历史结论及来源，不冒充仍可读取的原始证据；涉及“当前/现有”的描述均指研究时基线9657d2a。后续实现与验收见 ../10-17-simplify-agent-queries/（research/ 下文档对应 ../../10-17-simplify-agent-queries/）。

核查日期：2026-10-17。本文仅覆盖实验用本机 OTP/Elixir 一手源码，不是生态选型最终报告。基线 `9657d2a`，产品模块未修改。

## 版本和原始证据

- 运行时：OTP **29.1.2**、ERTS **17.1.1**、Elixir **1.20.4**（编译目标 OTP29）。不是仅根据 PATH 推断。
- `:erlang.system_info/1`、`System.version/0`、运行安装目录 `releases/29/OTP_VERSION` 一并由实验记录。
- 原run `20261017T122252-5c3d06fc` 的runtime行曾核验上述版本；原始记录已清理，当前仅留存摘要。
- 本机源码根目录：`/nix/store/cv5n8x0z3hzaxxdq9zi2mn9aznck46v4-erlang-29.1.2/lib/erlang`。
- `lib/kernel-11.0.4/src/rpc.erl` SHA256：`e62d0420294e320fa9185c43a9dff1f8b14438704a78386341a149d2a4896fe8`。
- `lib/kernel-11.0.4/src/erpc.erl` SHA256：`7e5615627bb94221eb9371046cda801922711672c09ceca21b4b2bf19f3572db`。
- 上述安装源码哈希保留；实验源快照与运行日志已清理。早期失败本无当时源快照，现不声称可从仓库精确恢复任何一轮实验。

## 1. 现代 rpc 不等于传统 rex

本机 `rpc.erl:492-493`：

```erlang
call(N,M,F,A,T) ->
    ?RPCIFY(erpc:call(N, M, F, A, T)).
```

`rpcify_exception`（约538-560行）把 erpc 的异常映射为 `badrpc` 等旧形状。正常命名 peer 实验中，暂停远端 `rex` 后，`:rpc.call/5`、`:erpc.call/5` 的 list/lookup 均成功，各独立3次；所以不能以 `rpc` 名称推断查询工作排进 rex。

`erpc.erl:297-313` 使用 `spawn_request(Node, erpc, execute_call, ..., [{reply,error_only},monitor])`，函数结果通过进程终止原因与 monitor 返回。`result(timeout,...)`（1389行）调用 `call_abandon/1`；后者（1352-1356行）使用 `spawn_request_abandon/1` 或 demonitor。这里的 abandon 不是“杀掉已开始的远端函数”。源码文档235-260行明确：超时/断线时函数可能已执行或将执行，调用方不再收到对应结果；用户函数自行发送的消息不在这个保证内。

本任务没有把所有 rpc 导出接口都等同于 erpc：`block_call/5`（531-535行）仍是 rex server call，且会阻塞 rex。本实验**没有运行 block_call**，也不推荐拿它模拟普通并行 RPC。

## 2. 真正经过 rex 的版本锁定内部协议探针

**非公共协议，只适用于本实验 OTP29.1.2，不是产品建议。** harness 启动时验证 `OTP_VERSION == "29.1.2"`，其他版本直接拒绝运行，防止错误套用内部消息。

```elixir
GenServer.call({:rex, remote},
  {:call, QueryTransport.Fixture, function, args, :user}, timeout)
```

- `rpc.erl:173-199` 的 `handle_call({call,...}, To, State)` 创建独立监控 worker，不在 rex callback 中直接等待业务结果。
- `:user` 由远端 rex 的 `set_group_leader/1`（约324-336行）解析为**远端本地** IO leader；实验函数不做远端 IO，不把 coordinator group leader 传过去。
- `rex_queue/1..3` 暂停 rex，原始记录包含 rex mailbox 中实际 `'$gen_call'` / `{call, Fixture, slow, ...}`；此时 Facts 中没有 worker。调用方约121ms超时后，才经 standard_io 恢复 rex；随后记录远端 start、complete、真实本地监控 DOWN。不是用现代 rpc 的结果替代 rex。
- 请求已经进 rex mailbox，调用方 GenServer.call 超时/alias失效不撤回该消息；恢复后仍启动这次有界工作。
- `rpc.erl:299-303` 的 rex reply 最终调用 `gen_server:reply`。传统探针在执行/回复断线后均观察到 nodeup（3/3）；现代 erpc/rpc 对照在同样有界函数里未见此回复重连。结果因果限定见实验发现，不升级为跨版本定理。

## 3. 隐含连接流量：rex 的节点特征观察器

`rpc.erl:375-417` 的 `start_nodes_observer/0` 与 `nodes_observer_loop/1`：

- 本地 `monitor_nodes(true)` 本身不主动连接；但处理 nodeup 后会用普通 `!` 向 `{rex,N}` 发送 `features_request`。
- rex `handle_info({From,features_request},...)`（约279行）也用普通 `!` 返回 features_reply。
- 因此在**尚未完成特征交换**时快速 connect→disconnect，待处理的 OTP 基础设施消息可能影响连接观察。单凭“最后调用的是 send_safe”不能归因。
- 两个未稳定握手的失败运行被保留：`20261017T121120-9ff376ca`（过强地要求 send返回必须noconnect）、`20261017T121228-62a496bb`（实际捕获返回ok后nodeup）。它们未启用 rex send trace，因此对这两次 nodeup 的具体发送者只能给出源码支持的假设，**不能声称已逐消息证明根因**。
- 最终 harness 在断线观察窗口前，通过两端 VM **本地**读取 `persistent_term` 中 rex feature ETS，等待双方确认 erpc 支持；Facts 还在本 VM trace rex observer 的 send，并经 standard_io读取。这个版本锁定的实验诊断不应成为业务代码依赖。
- 最终连接窗口无 RPC、remote monitor、remote IO；`:peer.call` 仅走 standard_io。正向 `Node.connect` 控制放在观察窗口结束之后。

## 4. OTP/Elixir 能力边界（源码核查，不冒充全部实测）

| 能力 | 本机源码锚点 | 可解决 | 不自动解决 / 本次实测范围 |
| --- | --- | --- | --- |
| erpc call / send_request + receive_response | kernel erpc.erl:297-313、418-424、497-548、1352-1356 | 调用关联、明确异常、超时后放弃结果 | 不等于取消远端工作；call 已实测，异步组合未单独运行 |
| GenServer.call / alias | stdlib-8.1.1/src/gen.erl:240-279 | alias去活后过滤迟到响应 | monitor可能建连；不能撤销已经入队的请求；本实验通过 rex/Server call 实际使用 |
| gen_server.send_request / receive_response | stdlib gen_server.erl:1328-1417、1500-1533；gen.erl:317-319、385-400 | 关联请求，receive_response超时放弃响应 | wait_response超时不等于放弃；异步接口未另行实测；send_request先创建monitor，不能只看后面的noconnect send就声称整体不建连 |
| disposable alias + send noconnect/nosuspend | 现有 Discovery.send_safe/2、Endpoint | 不用远程monitor/IO的发送；失效alias丢弃晚回复 | 不保证远端函数立即停止、不撤回Server mailbox；现有Endpoint已实测 |
| Task.Supervisor async_nolink + 显式shutdown | 本机 Elixir `lib/elixir/lib/elixir/lib/task/supervisor.ex:175-320` | 本地/指定监督者拥有临时task、隔离普通异常传播 | 不等于分布式取消；caller退出和超时后的回收必须明确拥有者/预算。此API未另建候选实现测试 |
| 独立临时worker + 远端函数本地预算 | 本任务 Fixture.blocked_read、slow | 即使caller死亡仍在自己预算内完成并DOWN | 不是立即取消，也不阻止rex恢复后才开工；已实测 |
| Endpoint lease | 现有 Endpoint.fresh_deadline/run_query | caller失联后有限回收实际controller/worker | 本轮约300ms，不是瞬时；已入队ref仍保留；已实测 |

GenServer.reply 的 alias 去活机制和“是否尝试建立连接”是不同问题：本轮传统 rex 探针即使调用方 mailbox 为空，仍观察到重连。因此不能由“没有晚回复”推出“没有网络扰动”。

## 限定结论

本机标准 RPC 足够执行安全、有限时长的只读函数，但默认不是“仅已连接节点且绝不自动连接”的传输，也不是严格分布式即时取消协议。是否接受后台有限完成，是需求取舍；不能由这些实验直接替换现有 Endpoint 契约。恢复阶段已在 [report.md](report.md) 整合生态方案、最小候选推荐与 AC 证据；随后独立review真实复跑一次full，结论PASS，见 [quality-review.md](quality-review.md)。该结论不改变上述语义限制或授权产品迁移。
