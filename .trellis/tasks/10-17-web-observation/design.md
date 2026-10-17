# Shared Observation Design

## Authority

[父设计 §4](../10-17-beamlet-web/design.md) 是拟议接口/限额的共同契约；当前源码证据在父任务 research/current-capabilities.md。实现前确认现有函数和测试；不得把拟议 API 当成已存在。

## Agent boundary

增加 snapshot(ref, view: :display)、subscribe(ref, sink, view: :display) 的 opt-in 重载。旧默认 API/tuple/credit 保持不变，subscribe 的 sink 负责 ack；统一 owner 投影，不新增 PubSub、事件重放或查询 endpoint。

新 display_metadata 创建选项仅含验证过的标题/preset/公共 option IDs（<=4096 序列化字节），与模型/工具行为分离。显示投影从现有 messages/pending/children 和进度产生，不从 Web 会话推断完整历史。stable entry id 与 turn 关联在消息接收/追加时由 Agent 记录，生命周期限于当前 incarnation 的对应上下文；不修改 neutral messages 的格式，不按浏览器接收顺序猜任务边界，仅保留必要元数据，不复制 transcript。

display target128KiB，最多32条上下文、16活动、每文本字段8KiB；还受现有全快照上限约束。空间不够时截断/省略 display 并保留原因，不挤坏原 base snapshot；模型上下文绝不因 UI 截断。活动实际执行节点不可得时标 unknown，不下钻 coordinator 私有状态。

## Runtime / Node boundary

拟议 Runtime.observation/0 由 Directory owner 计算安全报告信息和 receipt age；Node.observation/0 返回启动配置声明角色与服务就绪事实；Node.observe(nodes) 有界聚合。最多32目标、8并发、5s总接收预算、1MiB完整返回。复用现有有限本地读取/erpc 隔离模式，不引入查询服务树或自动重试。

Node 可在 Routes 的受信元数据中保留启动角色的安全副本，但不复制整个配置。观察结果与失败分开，连接/就绪/报告新鲜度分开；不跨 VM 比较 monotonic 时间，不承诺原子快照或容量预留。

## Compatibility and rollback

Agent 继续无 Phoenix 依赖；新读取为 additive。Identity discovery 仍只读身份岛，慢显示读不污染 list/lookup。首先确保 CLI 默认投影测试不变，再新增显示视图。回滚停用新调用/可选字段，不修改已创建实例或承诺恢复。
