> Historical transport requirements are superseded by [simplify-agent-queries](../10-17-simplify-agent-queries/design.md): finite local/erpc reads, no Endpoint or leases, and standard OTP reconnection after the entry precheck. Public identity/attachment contracts remain.

# Agent 发现、查询与重新附着接口

> 归档收尾（2026-10-17）：用户明确要求归档剩余六个任务。实现、独立检查及父任务最终AC1–AC9验收已完成；最终196项普通/23项命名测试、双copied release与静态门禁的历史范围见父任务research/final-acceptance.md，提交记录见research/commit-execution.md（子任务从父目录查阅）。旧发现传输语义以后续simplify-agent-queries任务为准。 下文“待验收/待提交/未授权归档”等描述保留为当时阶段的历史记录，最终状态以task.json及本收尾说明为准。任务未建立独立PR，使用归档命令支持的--skip-branch-validation，不伪造分支或合并记录。

## Goal

让 interaction 客户端查找并附着集群中已有存活 Agent，而不依赖其创建会话；接口可供未来 Web 复用。

## Background

`Beamlet.Agent.Server.start_link/1` 通过 authority 本地 Registry 注册 ID，Server 持有真实 Ref。Registry/Authority 重启会使 Agent 失效；本任务增加存活查询，不恢复已丢失状态。

## Requirements

- 覆盖父任务 R2/R4/R7/R9；来源：`../10-17-node-host-split/prd.md`。
- Agent 库提供 authority-local 与显式 authority 的有界列表/lookup；不反向依赖 Node/CLI。
- Node 库聚合已连接可信节点的查询，不进行隐式连网或无界 atom 创建。
- 使用 authority+ID 区分同名；列表身份与 attach 竞态必须明确，不能默选同名候选或将旧 Ref 自动绑定新实例。
- 仅投影安全身份信息；不读取/泄漏模型 binding、凭据、原始 options 或历史。附着取得当前实例真实 Ref，不创建、转移、改绑定或隐式输入。
- 部分结果、不可达、非 authority、未找到、超时/限制有明确有界结果，不能伪装为完整空列表。
- 客户端退出不影响 Agent 生存；权限沿用可信 distribution 集群，不新增多租户权限体系。

## Acceptance Criteria

- [x] 本机/实际命名远程 authority 列表和 lookup 可用，非 authority/未找到/不可达可区分。
- [x] 多 authority 同名 ID 可区分；旧列表指向的实例已经替换时不静默附着替代实例。
- [x] A 创建后退出，B 获取同一 authority/PID/incarnation，读取当前快照并继续操作。
- [x] 关闭/ID 复用/断线/authority 重启的查询竞态不重建、不重放、不重绑旧 Ref。
- [x] 节点数、并发、时间、结果大小有界；部分失败可见且 helper 及时退场，无敏感数据泄漏。
- [x] 非 CLI 宿主能使用接口，不依赖终端、daemon 产品或 Web 新功能。

## Ordering and Scope

依赖 `../10-17-node-library` 的可信连接约定；CLI 依赖本接口。验证可用测试宿主，不要求 daemon 产品存在。实际计划在 daemon 后、CLI 前实施。无持久化恢复、全局永久身份、线性化集群快照、历史重放、所有权迁移或业务重试。设计/步骤见同目录 design.md / implement.md。
