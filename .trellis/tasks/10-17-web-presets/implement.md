# Host/Preset Execution Plan

## Preconditions

- [x] 父子最终规划已获用户“批准”（2026-10-17）；observation metadata/read 契约经独立检查、Runtime修复及spec同步后完成工程验收，见 ../10-17-web-observation/research/acceptance.md。
- [x] 阅读父设计 §2/§3/§5、源码证据及 JSONL spec；确定 one-Node-per-VM teardown fixtures。

## Ordered work

- [x] Web manifest 增加实际直接依赖；Host 配置 disabled 默认，严格校验再启动角色。
- [x] 复用 Cluster 实现受信 peer 单次连接、超时和 owner teardown；local non-distributed 走显式本地路径。
- [x] 实现 immutable startup preset/options + browser-safe 描述；未知键/超量/非法引用 fail safely。
- [x] 实现 draft resolve/reset、环境与精确 tools/catalogue 组合、风险/有效配置摘要；不回写 preset。
- [x] 实现 Agent create-then-input 安全适配、确定失败与未知结果；阻止自动业务重试。
- [x] 实现有界 handle 导航和 stale/expiry 语义；仅 safe metadata 不保存 transcript。
- [x] 测试 local/remote role 组合、伪造选择、秘密不泄漏、metadata/配置不变和加载隔离。
- [x] 给出 trusted deterministic 示例与非本机暴露保护说明；更新已实现 spec。

## Validation and rollback

计划：mix format --check-formatted；mix compile --warnings-as-errors；mix test apps/beamlet_web/test apps/beamlet_node/test；mix credo --strict；mix dialyzer；mix sobelow。按父 implement.md 进行真实 named peer 与受影响 release 闭包回归。

回滚 disabled host 和匹配配置；不修改已创建 Agent、不清理业务实例来修复测试污染。普通加载有副作用、有效工具与 catalogue 不一致、credential 进入 assigns 任一项均阻塞工作台实施。
