# Node 库化与 daemon/CLI 宿主拆分

## Goal

分离可嵌入 Node 能力与可执行宿主，交付 daemon 和轻量会话式 CLI，支持重新查找/附着集群中的存活 Agent，并使未来 Web 可以直接集成三种角色。

## Background

- 用户已在提交 `0fed1b1` 创建 daemon/CLI 的 OTP Application/Supervisor 骨架；复用现有工程。
- 当前 Node 含自动启动、CLI 和 release 职责，需要迁移而非复制。CLI 骨架已声明 Owl/ucwidth，不以完整 TUI 为目标。
- Agent ID 仅在 authority 本地 Registry 内唯一；Ref 含 authority/id/incarnation/pid。缺少公开查询是当前实现缺口，不是本次产品限制。
- 产品决策与最终规划已获用户“确认”批准；四个子任务依次实现并通过独立 review。父任务负责最终集成验收，commit/archive 仍待授权。

## Requirements

- R1 — Node 是库，不发布独立可执行产物，不因依赖加载自行装配角色或读取宿主配置；由宿主管理生命周期。
- R2 — 保留显式监督、配置校验、全部七种启动角色组合以及 Agent/Runtime 业务接口；未来 Web 可在一个节点集成 interaction/authority/executor，不依赖 daemon/CLI/终端。
- R3 — Daemon 默认 authority+executor，不提供 interaction。发布产物携带两类能力的代码，程序启动时通过可信配置选择 authority-only、executor-only 或两者组合；不按这三种选择另建角色专用 release。
- R4 — CLI 固定 interaction，采用单进程持久交互会话，支持连接集群、创建、列表/查找、附着、输入、观察/状态、停止和关闭。别名仅为本地句柄；CLI 退出、断线或 detach 不关闭 Agent，新会话可重新附着。
- R5 — 当前仅交付 daemon、CLI 两个 `mix release` 产物。后端产物不包含 Web/不需要 Web secret，CLI 不依赖或启动 daemon。通过可信配置提供本地资源/provider/工具和集群连接参数。
- R6 — 删除旧 `Beamlet.Node.CLI` 名称、Node Application 自动启动、`:beamlet_node, :boot` 配置和 Node release，不加兼容转发层；迁移仓库调用、配置、脚本、测试与说明，避免双份实现。
- R7 — 保持模型绑定不可变、凭据隔离、异步 Operation、订阅 credit、停止/不确定性和无业务自动重试/重放语义。
- R8 — 角色仅在启动时确定，无运行期切换或热配置系统；普通 umbrella 测试/应用加载不得接入真实集群、抢占 Node 名称或等待终端输入。
- R9 — 存活 Agent 发现/查询作为可供 CLI/Web 共用的库级接口，覆盖已连接的可信节点。附着获取真实活 Ref，不转移 authority、不重建实例、不改模型绑定、不隐式输入。明确区分未找到、不可达和部分结果，且不泄漏 binding/凭据。

## Task Map

| Child | Deliverable | Explicit order |
| --- | --- | --- |
| `10-17-node-library` | Node 可嵌入接口、共享连接、旧 CLI 职责迁移 | 首先 |
| `10-17-daemon-host` | 三种启动方案、部署配置、连接与 daemon release | Node 之后 |
| `10-17-agent-discovery` | Agent 列表/lookup 与有界集群聚合接口 | Node 之后，CLI 之前 |
| `10-17-cli-host` | 会话命令、重新附着、CLI release 和跨宿主验收 | 依赖前三项 |

父任务负责需求、跨子任务验收和最终集成复核，不作为默认实现目标；父子关联本身不表达依赖。实际顺序为 Node → daemon → discovery → CLI，子任务均记录所需前置交付。

## Acceptance Criteria

- [x] AC1/R1：仅启动 Node 库不出现 Node/Authority/Executor 服务，不需要配置或终端。
- [x] AC2/R2：测试宿主覆盖七种角色组合，包括三角色同时运行；共享接口无宿主反向依赖，Web 原行为不变。
- [x] AC3/R3：同一复制的 daemon release 在三份不同启动配置下完成命名启动/角色断言/RPC/停止；拒绝 interaction；默认启用 authority+executor。
- [x] AC4/R4：真实 CLI 会话连接 daemon，完成创建、查找/附着、输入、观察、状态及停止/关闭；退出/断线/detach 仅清理客户端观察。
- [x] AC5/R5：两个 copied release 均检查闭包、配置隔离、命名启动/停止；daemon 不含 CLI，CLI 不含 daemon，均不含 Web、不需要 Web secret。
- [x] AC6/R6：旧模块、配置和 release 入口移除，无兼容转发；脚本、说明与测试迁移到新入口。
- [x] AC7/R7：普通、实际命名 distributed、确定性 HTTP/工具链及 copied-release 回归通过并记录实际数量/失败；不宣称物理多机或付费模型验收。
- [x] AC8/R8：没有运行中角色变更接口；umbrella 加载/测试不意外启动宿主；未来 Web 组合由库级测试证明。
- [x] AC9/R9：客户端 A 创建后退出，B 发现并附着同一 authority/PID/incarnation；覆盖多 authority 同名、查询/关闭竞态、ID 复用、断线及部分查询失败，无敏感投影泄漏，旧 Ref 不会静默重绑。

## Out of Scope

- Web/TUI/Desktop 新功能，escript/容器/桌面等其他打包方案。
- 运行期角色变更、热配置、全局自动发现/集群管理平台、多租户授权系统。
- Agent 状态持久化、authority 重启后的恢复/迁移、全局永久唯一 ID、历史重放、故障转移、自动业务重试。存活 Agent 的跨 CLI 会话重新附着属于范围内。
- 新模型协议、真实付费调用、远程实际部署或物理多机验收。

## Planning Gate

最终规划摘要后已收到用户明确“确认”。四个子任务按顺序完成实现和独立检查，父 AC1–AC9 验收通过；详见 research/final-acceptance.md。父任务保留协调身份，Git 提交、归档和 journal 尚未执行。
