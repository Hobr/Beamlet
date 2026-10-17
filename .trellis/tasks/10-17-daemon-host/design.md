# Daemon 宿主设计

## Prerequisite and role model

依赖 node-library；遵循父 design.md 的 3/4/7/8 节，需求 R3/R5/R6/R7/R8。一个 release 包含 authority/executor 代码，启动配置选择 [:authority]、[:executor] 或默认 [:authority, :executor]。only 不裁剪代码，interaction/重复/空角色拒绝，运行期无角色更新接口。

## Startup and configuration

Daemon.Application 默认启动空宿主监督树，enabled: true 时启动 {Beamlet.Node, validated_options}。release 的 daemon_runtime.exs 读取绝对 BEAMLET_CONFIG，写入 :beamlet_daemon 的 enabled/node/allowed_nodes/peers 配置。默认 roles 在 daemon 配置归一化处一次填充，Node 继续负责共享结构/资源/provider 校验，不复制两份底层约束。

可信配置可以设置 tools/workspace roots/pools/registries，不预配用户模型凭据。Node 就绪后由独立启动连接任务遍历最多32 peers，复用 Cluster；不在 Supervisor.init/Agent callback 中阻塞网络。一次连接失败安全报告但不停止本机可用服务，无后台重连/业务重放。配置结构非法则在启动任何角色前失败。运行期不暴露重配入口。

## Packaging migration

- 添加 Daemon→Node 直接依赖，复用已有 OTP 骨架。
- 根 mix.exs 将旧 release 替换为 beamlet_daemon，backend build 集合加入宿主，继续排除 Phoenix 和隔离 _build/backend。
- 新 daemon_runtime.exs、daemon.example.exs、迁移 rel/env.sh.eex 与服务说明，移除旧 Node 启动配置/backend_runtime.exs（CLI 配置后续独立新增）。
- 保留 RELEASE_NODE/COOKIE/BEAMLET_CONFIG、长名字、服务固定端口与控制 helper 端口0；不记录 secret/cookie。
- 迁移 check-release.sh/check-named-release.py 到 daemon 三种启动方案；七种组合仍在 Node 库测试验证，不再要求 daemon 发布 interaction。
- CLI 子任务随后扩展到两产物验收，不能因为后台尚缺 CLI 产物保留 Node executable。

## Failure and rollback

默认双角色、一角色/配置失败和连接失败分别测试。退出服务遵循原 Node 停止/不确定性语义。旧产物只能与旧配置整套回滚，混合 build/协议不受支持；不把服务重启说成恢复 Agent。
