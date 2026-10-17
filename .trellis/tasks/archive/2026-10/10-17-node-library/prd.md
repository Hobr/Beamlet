# Node 可嵌入库与共享接口迁移

> 归档收尾（2026-10-17）：用户明确要求归档剩余六个任务。实现、独立检查及父任务最终AC1–AC9验收已完成；最终196项普通/23项命名测试、双copied release与静态门禁的历史范围见父任务research/final-acceptance.md，提交记录见research/commit-execution.md（子任务从父目录查阅）。旧发现传输语义以后续simplify-agent-queries任务为准。 下文“待验收/待提交/未授权归档”等描述保留为当时阶段的历史记录，最终状态以task.json及本收尾说明为准。任务未建立独立PR，使用归档命令支持的--skip-branch-validation，不伪造分支或合并记录。

## Goal

将 Node 收敛为显式启动的共享库，供 daemon、CLI 与未来 Web 使用。

## Requirements

- 覆盖父任务 R1/R2/R6/R7/R8；来源：`../10-17-node-host-split/prd.md`。
- 依赖启动不装配 Node、不读取配置文件或终端。保留 Supervisor child_spec/start_link 和全部七种角色组合。
- 共享连接/可信名称校验不依赖 CLI；不引入对 daemon/CLI/Web 的反向依赖。
- 删除旧 Application 自动启动和 `:boot`；旧 CLI 名称不保留兼容层，终端适配器与所属测试迁往 CLI 应用。
- Agent 发现由独立 discovery 子任务实现；Node 不拥有 Agent 注册表或生命周期。
- 保持原有编排、能力校验、凭据、订阅与不确定执行语义。

## Acceptance Criteria

- [x] 库加载无需宿主配置且不产生 Node/Agent/Executor 服务。
- [x] 测试宿主显式监督七种启动角色组合，并验证三角色同时使用无终端依赖。
- [x] 可信节点名校验/连接可被非 CLI 宿主调用，输入/节点数有界且不对任意业务字符串 atomize。
- [x] CLI 终端行为与测试完成迁移，Node 内不再有旧 CLI 名称/自动启动入口；相关测试保持可运行。
- [x] 现有生命周期、模型绑定、并发工具和订阅回归保持；未加入运行中角色切换接口。

## Ordering and Scope

首先实施。daemon/discovery/CLI 依赖本子任务共享接口。旧 Node release 在 daemon 子任务正式替换，完整 CLI 命令循环在 CLI 子任务交付；本阶段只迁移必要适配器/测试，避免复制实现。复杂设计和步骤见同目录 design.md / implement.md。
