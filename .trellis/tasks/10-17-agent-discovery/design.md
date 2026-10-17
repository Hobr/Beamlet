# Agent 发现与附着设计

## Ownership and APIs

依赖 node-library，遵循父 design.md 第5节；需求 R2/R4/R7/R9。Agent 库拥有本机/远程 list/lookup；Node.Agents 只负责已连接可信节点聚合。不能让 Agent 依赖 Node。

- Agent.list(authority) 返回有界身份 descriptors：authority/id/pid；Registry.select 枚举唯一 ID，不对每个 Agent 串行请求 snapshot。
- Agent.lookup(authority,id) 查 Registry 后向真实 PID 请求 :ref，核对 authority/id/pid，保留真实 incarnation；受总 deadline 约束，不自行拼 Ref。
- Node.Agents.discover(nodes) 最多32个明确可信已连接节点，无隐式 connect。最多8并发、总接收 deadline 5秒、结果总序列化1MiB上限，结果含 agents/failures/complete。

具体返回与错误见父 design；查询方法验证输入并返回安全固定原因，不带原异常。not_authority 不得被当成空的 authority；部分失败与超限不得产生“整个集群没有 Agent”的假象。complete 只针对请求集合。

## Identity and races

ID authority-local；列表不是全局原子快照。descriptor 附着支持 expected PID，替换实例返回 stale_agent；显式 authority+ID lookup 选择当前实例。旧 Ref 不自动重绑，新 lookup 不自动提交 input。查询后进程可能死亡，后续控制继续使用 Agent 自身 incarnation/PID 检查。

无全局注册中心、磁盘索引、Session 生存绑定、独占 attach 锁或新鉴权体系。CLI/Web 的重新附着只是获得当前活 Ref 和 snapshot/订阅；authority 重启不恢复旧 Agent。

## Resource and secrecy constraints

list 不读取 GenServer 私有 state、model binding、历史或配置；避免 :sys.get_state。lookup 等待单目标真实 Ref。聚合 worker 在调用者退出/预算结束时回收，不能只结束 receive 然后留下阻塞 RPC 后台运行。结果限制应用于完整信封，触顶必须显式 partial/limit。

## Files and validation surface

修改 apps/beamlet_agent/lib/beamlet/agent.ex，必要时新增 agent/discovery.ex 辅助保持 facade 简洁；Node 新增 node/agents.ex 聚合。测试分别属于 Agent 与 Node，使用真实 peers，并保留无反向依赖检查。

重点：同名 authority、ID复用/列表后关闭、悬停 Server lookup、RPC 分区、部分结果和 caller DOWN 时 helper 退出；不能通过多次业务请求掩盖失败。

## Approved transport amendment (implementation)

Supervisor explicitly approved an Agent-owned supervised `Discovery.Endpoint`, no
rex transport. OTP29.1.2 rpc.erl173-195/302 and gen.erl549-556 show rex replies use
ordinary sends; suspended rex can admit queued calls after expiry. A connected
precheck around erpc likewise cannot exclude reconnect. Neither is used here.

Standalone AuthoritySupervisor starts the endpoint last in authority mode, coupled
one_for_all to Registry/Agents. Node authority role uses that child only; other
role sets start the same endpoint in non-authority mode, after shared children.
Dependency loading starts nothing. No host-specific tree or second registry.

All query/control/reply sends use noconnect/nosuspend. Only local processes are
linked/monitored. A passive offer handshake (bounded256 entries, expiry5s) must be
confirmed by the requesting helper before spawning work; expired queued confirms
are discarded. Endpoint callbacks never call Registry/Server. Admitted controllers
own linked workers, outside-call timers and a250ms requester heartbeat lease;
loss of caller kills local helpers, remote lease expires within a finite bound
without requiring a reconnect/cancel acknowledgement. Each request lives at most5s
from local admission; local total receive deadline remains5s from API entry.
No cross-node monotonic clocks are compared. Query replies use disposable aliases;
late replies cannot accumulate in public callers. Query work is read-only; passive
queued offer handling may occur after caller loss, but cannot admit work without
confirmation. Endpoint retains at most256 pending/active requests and only identity
results (128 agents per authority,1MiB envelope cap).

Before-dev boundary: Agent owns identity projection, validation, query protocol and
worker lifecycle; Node owns trusted-connected aggregation only. Existing Server
:ref handler is reused; no private state, model or business lifecycle changes.


## Queued admission repair (new candidate)

The original frozen candidate's confirmation was insufficient: it could remain
queued past the public deadline and spawn work before a fresh requester response.
Confirmation now creates only a passive, quota-accounted controller. Before any
Registry/Server query, it issues a fresh nonce challenge through the disposable
alias. The requester checks its original deadline before confirming, answering a
challenge, or accepting a result, including messages already queued at expiry.
The public deadline is allocated before task startup, not inside the helper.

The endpoint passes a local absolute deadline to the controller, so controller
startup cannot reset the sampled confirmation budget. Each admission/heartbeat
response carries the requester's current remaining duration. The controller
subtracts the entire locally measured challenge roundtrip (conservative), clamps
to its existing deadline, and rejects responses received after that deadline or
the250ms lease even if the response is already in its mailbox. Neither node
compares the other's timestamps. Worker startup and the final Server call also
check the deadline. Unanswered passive controllers retire within the lease plus
scheduling; pending offers retain their5s expiry and the combined256 quota.
No new endpoint, retry, connection policy, public API or dependency is introduced.

Freshness is an observed exchange, not atomic remote liveness or hard real-time
execution: ordinary scheduling and distributed death races remain possible after
a timely response. No instantaneous remote-death detection is claimed.
