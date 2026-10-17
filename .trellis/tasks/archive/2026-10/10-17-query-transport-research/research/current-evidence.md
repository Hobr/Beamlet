# 规划阶段证据（不是实验结论）

> 留存状态（2026-10-17）：用户已接受后续 simplify-agent-queries 实现，按约定清理本任务的 results/、experiments/ 及专用 .gitignore。原始记录、失败日志、源快照和实验脚本不再随仓库提供，不能按原命令复现。本文保留历史结论及来源，不冒充仍可读取的原始证据；涉及“当前/现有”的描述均指研究时基线9657d2a。后续实现与验收见[已归档实现任务](../../10-17-simplify-agent-queries/prd.md)。

## 已检查的本地事实

- 基线提交：`9657d2a`；创建本任务前工作区干净。
- PATH 中可用工具路径标识 Elixir 1.20.4 与 OTP 29.1.2。执行阶段仍需通过运行时报告版本，不能只凭安装路径断定运行版本。
- `apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex:11-32`：Registry、Resources、Delegations、Agents、Discovery.Endpoint 位于同一个 one_for_all 监督树。Endpoint 失败存在连带重启风险；具体 PID/incarnation 影响待隔离实验验证。
- `apps/beamlet_agent/lib/beamlet/agent/discovery/endpoint.ex`：现有实现使用 offer/confirm、新鲜 nonce challenge、查询 worker、心跳租约与本地 deadline；不能把旧版两阶段握手当作当前实现。
- `apps/beamlet_agent/test/beamlet/agent/discovery_test.exs`：已有 suspended Server、caller loss、deadline、排队确认与心跳过期用例。仅阅读，当前任务尚未运行。
- `apps/beamlet_node/test/beamlet/discovery_distributed_test.exs:1-130`：已有真实 `:peer`、`connection: :standard_io` 和低 scheduler 数模式，可复用隔离思路；observer 的 distribution monitor/远端 RPC 可能污染连接实验，不能照搬所有观测方法。
- `.trellis/tasks/archive/2026-10/10-17-agent-discovery/design.md` 与 `.trellis/spec/backend/agent-orchestration.md`：记载了排除 rex/erpc、无自动连接及有界回收的既有契约。本任务把它们作为待核查的项目约束和历史理由，不把它们当实验结果，也不修改它们。

## 已知待核查项

1. 当前 OTP 的 rpc 调用何时使用 erpc，哪些兼容路径真正经过 rex。
2. 放弃响应与取消执行的区别；无远端主动取消但有远端有限时长，是否已足以满足低扰动只读查询。
3. 已断开、预检查后断开、执行中断开、结果返回时断开分别是否引入重连。
4. 查询端点与 authority 的同库归属是否被误当成同故障域要求。
5. 社区方案的适用性、版本支持及维护状态仍需官方文档、源码、发布记录验证。

## 用户意图与研究边界

用户希望查询尽量无感知无影响。解释为需要研究不改业务状态、不将客户端/查询故障传播成 Agent 终止的方案；不承诺零 CPU、零消息、零网络影响。严格取消、禁止过期准入、绝不自动建连与维护成本需要分别评估，不代用户预先放宽或升级现有契约。

本文件只记录规划所需事实；完整生态调研及实验待规划批准后进行。
