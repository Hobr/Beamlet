# Daemon 宿主与 release 部署

> 归档收尾（2026-10-17）：用户明确要求归档剩余六个任务。实现、独立检查及父任务最终AC1–AC9验收已完成；最终196项普通/23项命名测试、双copied release与静态门禁的历史范围见父任务research/final-acceptance.md，提交记录见research/commit-execution.md（子任务从父目录查阅）。旧发现传输语义以后续simplify-agent-queries任务为准。 下文“待验收/待提交/未授权归档”等描述保留为当时阶段的历史记录，最终状态以task.json及本收尾说明为准。任务未建立独立PR，使用归档命令支持的--skip-branch-validation，不伪造分支或合并记录。

## Goal

复用 OTP 骨架交付可配置的常驻 daemon，取代 Node 的可执行身份。

## Requirements

- 覆盖父任务 R3/R5/R6/R7/R8；来源：`../10-17-node-host-split/prd.md`。
- 一个 daemon release 携带 authority 与 executor 代码；启动配置支持 authority-only、executor-only、authority+executor（默认）。拒绝 interaction、空/重复/非法角色，运行中不能切换。
- 宿主负责可信配置加载、默认值、生命周期和集群连接策略；配置 provider/资源池/工具及连接参数，不在 executor 静态配置用户模型 key。
- 提供独立 `mix release`，迁移旧 Node release 与部署配置/检查/说明；不包含 CLI/Web，不需要 Web secret。
- 未显式启用时，普通 umbrella 应用启动不连接集群、不启动 Node；release 显式启用宿主。

## Acceptance Criteria

- [x] 默认及两个 only 方案均以同一产物正确启动，进程断言符合选择，非法方案明确失败且不泄漏配置/凭据。
- [x] authority-only 无需 workspace 或用户 key；executor-only 不启动 Agent Registry，模型/工具仍走 Gateway。
- [x] 命名节点显式连接并执行确定性 turn；连接失败可观察且不触发业务重试/重放。
- [x] copied release 在源码/deps 外完成三个方案的命名启动/RPC/停止，服务/控制端口不冲突。
- [x] 闭包不含 CLI/Web，Node 不再作为发布入口，普通 Web 缺 secret 行为不被放宽。

## Ordering and Scope

依赖 `../10-17-node-library`。CLI release 与最终两产物集成由 CLI 子任务/父任务交付。不按角色分别裁剪/编译产物，不开发热配置、自动入群平台或其他发布方案。设计/步骤见同目录 design.md / implement.md。
