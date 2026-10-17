# 轻量 interaction CLI 与 release

## Goal

复用 OTP 骨架提供轻量会话式客户端，便于快速使用、测试和重新附着 Agent，而非完整 TUI 产品。

## Requirements

- 覆盖父任务 R4/R5/R6/R7/R8/R9；来源：`../10-17-node-host-split/prd.md`。
- 固定 interaction，不启动 authority/executor/daemon。显式启用后提供单进程持久交互会话。
- 支持可信连接、显式 authority、创建、列表/查找、附着、输入、观察/状态、停止 turn、关闭 Agent、detach/退出及帮助。
- 使用会话别名保存真实 Ref，但新会话可以查询并附着其他客户端创建的存活 Agent，不要求重复提交创建凭据。
- 共享发现/控制能力来自库；终端适配器/测试迁入 CLI，删除旧 Node.CLI 名称，不加兼容层。
- 观察保留 credit、显示/事件/时间上限；detach/退出/断线只清理客户端资源，只有显式 close 请求关闭，不对失联节点宣称远程关闭成功。
- 使用独立 `mix release`；已有 Owl/ucwidth 不意味着增加全屏 UI、终端框架或其他发布方案。
- 普通 umbrella 加载不等待 stdin、不抢占 Node，不打印或记录模型创建凭据。

## Acceptance Criteria

- [x] 普通应用加载无 Node/stdin 副作用；显式运行 CLI 仅 interaction 就绪。
- [x] 真实命名连接 daemon 完成创建、列表/查找、附着、输入、观察、状态、停止/关闭，不要求 IEx 手工协议。
- [x] A 退出后 B 可附着同一实例继续操作；detach/EOF/退出不关闭 Agent、无输入重放。
- [x] 非法命令/配置、同名 ID、死 Ref、断线、超时/事件上限和订阅/helper 清理均有测试。
- [x] copied CLI release 无源码/deps 也能通过 stdin 脚本完成操作并正常退出；不含/启动 daemon/Web，不需要 Web secret。
- [x] 原 CLI/HTTP→工具→模型集成覆盖迁移后仍有效，无旧名称兼容转发或双份实现。

## Ordering and Scope

依赖 `../10-17-node-library`、`../10-17-agent-discovery`；跨宿主验收依赖 `../10-17-daemon-host`。本子任务最后实施并完成两产物构建/验收脚本集成。无重启恢复、TUI/Web/Desktop 新功能、业务重试或其他打包方案。设计/步骤见同目录 design.md / implement.md。

## User steering: reuse installed Owl

CLI presentation must reuse installed Owl rather than build parallel terminal
utilities. Preserve exact bounded UTF-8 input, piped EOF, injected IO, safe errors,
real Ref semantics and watch credit ownership. No full-screen TUI or dependency
installation/version change is requested.
