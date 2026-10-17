# Management Design

## Authority and boundaries

遵循[父设计 §6](../10-17-beamlet-web/design.md)。在现有 Phoenix browser pipeline 下增加 /admin/nodes、/admin/presets、/admin/diagnostics 的只读 LiveViews，使用同一 shell 和 inspector，导航不是权限检查。

## Data flow

- nodes：Host trusted target names → Node.observe 的公开安全结果 → 展示 connection/readiness/freshness 和当前 available pools；source unknown/partial 直接表达。分布式时长用源读出的 age 和本地接收时间，不跨机减 monotonic 时间。
- presets：与创建表单相同的 Presets.safe descriptors → defaults/有效引用/配置来源摘要；不投影 private binding 或 executor settings。配置来源是安全类别/标识，不暴露凭据文件内容。
- diagnostics：selected live handle → opt-in Agent display 与已存在关联 → 共享活动检查。没有 operation/placement 数据显示未知，不建立持久 trace collector 或任意日志查询。

刷新至多一个页面级 bounded read 在途，定时器/任务随页面退出销毁；继承32目标/8并发/5s/1MiB外层合同。浏览器切页不得创建 Node 连接或执行 provider probes。无报告不是节点死亡，配置存在不是实际 provider 连通证明，可用容量不是预留。

## Security/compatibility/rollback

无修改配置/任意 RPC 等事件处理器；unsafe query params 只可匹配现有安全 handle/ID。用户内容与错误默认 escaping，不 dump raw inspect。保持原 dev dashboard/debugger 路由门控，不把 LiveDashboard 当产品节点页。部署保护与父任务相同，不实现角色账号。

回滚去掉 admin 路由/导航，不影响 workbench 的实际调用或业务实例。未来 metrics/history 不是本阶段占位数据。
