# Node 库与共享连接设计

## Contract and ownership

遵循父 design.md 的 2/3/4/7 节；来源需求 R1/R2/R6/R7/R8。核心 seam 是 {Beamlet.Node, opts}，宿主拥有启动/关闭时机。保留 start_link/1、configuration/1、profile/1、catalogue/0 和 Supervisor child_spec，不新增管理其他宿主的启动接口。

删除 node/application.ex 及 mix.exs 的 mod callback；application 元数据仍可声明必要 OTP 依赖。Node 的 Supervisor/Routes/Provider/Runtime 不因库化而删除。角色配置仍支持全部七种组合，现有 one_for_all 和 Provider→Runtime 启动顺序不变。

## Shared connection API

将旧 CLI.authority/connect 的非终端逻辑迁入 Beamlet.Node.Cluster：
- authority(name, allowed) 保留最多32名字、255字节和显式可信 allowlist 校验，仅匹配允许项才 atomize。
- connect(name, allowed) 做一次有界连接并返回安全结果，无业务重试。
- 提供已连接可信节点集合供 Node.Agents 使用；不自动连接发现的字符串。
原 Agent input/snapshot/stop/close 继续由 Agent facade 提供，不再为每个接口增加无意义 Node 包装。

## Terminal migration and files

- 修改 apps/beamlet_node/mix.exs，删除其 Application；新增 node/cluster.ex 和测试。
- 将 node/cli.ex 的终端客户端移到 apps/beamlet_cli/lib/beamlet/cli/client.ex，更新 namespace，不保留旧名。
- 同步 CLI 显式 Node/Agent 依赖，保持生成 Application 空启动，避免提前产生冲突。
- 将 cli_test.exs 和终端所属 release_integration_test.exs/必要 fixture/test_helper 迁入 CLI，避免 Node 测试依赖自己的上层宿主。distributed 排除配置同步迁移，不降低原断言。
- Node tests 保留角色、Provider、模型 binding 和 Gateway 合成验证。Core Agent/Runtime/Harness 仅在迁移必需引用时修改，不改变业务循环。

## Compatibility and rollback

显式 Node/Agent/Runtime 接口保留；旧 Node.CLI/:boot 不兼容是用户批准的迁移，不提供双入口。根旧 release 会在下个 daemon 子任务替换；跨阶段旧检查暂不执行不代表可保留到最终交付。

一 VM 一套固定注册名保持不变；七角色测试串行显式监督/清理，或用独立 peer，不能让生成的宿主自启。按本子任务差异精确回退，不重置用户 staged 文件。
