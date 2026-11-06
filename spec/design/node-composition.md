# Node 与角色组合

## 已确认的目标

Node 是组合与生命周期容器, 不是业务执行角色. Client 提交意图和读取结果, Authority 持有权威 Operation 记录并授权, Worker 接纳授权并执行. Runner 可指 Worker 内部的执行机制, 不作为对外角色名. 执行角色统一使用 Worker, 不保留 Work 作为另一种角色名.

消息会话, 网络监听与连接, 遥测导出, 生命周期管理及未来存储是 Node 基础设施. 它们独立于业务角色配置. 内嵌消息会话不等于内嵌 broker/router; 遥测 exporter 不等于 collector. 当前不新增遥测平台或通用插件框架. 多个角色可共享消息会话, 但不共享授权权力或账本.

同 Node 的绑定角色使用类型化交付, 保留接纳与证据校验步骤, 不绕网络或 JSON. 跨 Node 通过 Adapter 编码交付. 连接必须实际提供路由可达性, 不承诺任意拓扑天然互通.

## 身份与请求

目标稳定身份为 NodeId, AuthorityId, WorkerId; 每次启动独立生成 NodeInstanceId, AuthorityInstanceId, WorkerInstanceId. 角色重启不得复用旧运行身份. 公告与心跳只表达观察, 不自动建立信任或授权.

配置模式必须提供稳定的 `node_id` 及每个角色的 `id`, 并单独提供角色运行 `instance`. Node 的运行 ID 每次启动随机生成, 启动日志记录 Node 与各角色的归属关系. 目前角色运行 ID 仍由启动方为本轮部署生成并通过静态配置交换, 不能复用旧值; 自动生成与公告驱动的实例解析尚未实现. `workers` 和 `authority` 引用仍是远端角色的运行实例 ID, Console 的 `--authority` 也仍指运行实例, 尚非稳定逻辑身份路由.

目标由 Authority 在接纳提交时创建 OperationId. Client SDK 自动创建 SubmissionKey; 同一 Authority 内同键同定义返回原 Operation, 同键不同定义冲突. 去重映射和 Operation 必须作为一次本地接纳建立. 相同意图的新提交仍是新 Operation. Console 不组装底层授权和信封; SDK 暂时只提供 Zenoh, 未来可替换为 socket/HTTP. SDK 丢失提交键及 Operation 引用后, 本阶段不保证恢复请求.

多个独立 Authority 管理不同 Operation. Client 显式选择目标, 查询引用保留归属, 不广播提交. 共享连接不代表共享 Operation 命名所有权或允许自动接管. 当前每个 Worker 绑定一个 Authority, 多 Authority 信任列表另行实现.

当前实际生成仅需要 UUID v4 与 serde, 移除未使用的 v5/v7 features. Kernel 保持不依赖 UUID 生成库.

## 生命周期与交付

目标流程为启动依赖, 启动角色并公告, 心跳观察; 退出时进入 Draining, 停止新接纳, 协作停止或等待在途工作, 保留和交付证据, 发布退出通知, 最后关闭网络及遥测. 退出只移除运行实例的可调度资格, 不删除授权与报告历史. 旧实例的退出通知不得移除新实例.

未开始任务可拒绝并注明 NodeShutdown, Effect::None. 已开始任务需要真实停止或完成证据. 不可确认的执行或外部效果保持未知; 关闭节点不自动证明普通失败或无效果. 不提供任意 future 的暂停恢复, 持久化记录不等于 checkpoint. 迟到证据必须保留.

本阶段后续交付目标为有界, 纯内存的确认与重投: Attempt 接纳回执和 Report 保留回执分开; 先接纳/保留, 后确认; 重复消息重复确认, 不重复执行. 重投复用原身份和内容. 限制队列, 次数, 退避和截止时间. 达到上限保留未确认状态, 不重建授权或自动改派. 有限重试不保证任意故障下最终交付, 也不解决跨重启或效果恰好一次.

## Worker 启动公告与心跳: 当前实现

配置模式下, Authority 为 `beamlet/v0/authority/<authority-instance-simple>/lifecycle/worker/*` 声明独立有界订阅, 与业务收件箱共享同一 Zenoh 会话. Worker 向该前缀下的 `<worker-instance-simple>` 发布一次 `worker_started` 公告. 严格 JSON 包含 `protocol_version: 0`, `kind: "worker_started"`, `node_id`, `node_instance_id`, `worker_id`, `worker_instance_id`, `authority_instance_id`. 单条公告最多 4096 字节; 不接受未知字段或其他版本.

每个 Authority 最多配置 64 个 Worker 实例, 观察表仅为这些实例预留槽位. 公告必须匹配实际路由及目标 Authority 实例. 同实例同内容为重复观察, 同实例更改 Worker 或 Node 归属时拒绝覆盖. 未配置的实例不能借公告进入观察表, 旧实例不会自动替换新实例. 同 Node 的 Worker 由组合入口直接交付同一类型的公告, 不编码或走网络.

运行实例允许列表只是一项绑定校验, 不是网络身份认证. WorkerId 与 Node 归属是未认证的自报元数据; 首次记录不证明这些稳定身份的所有权. 公告不会建立新的信任关系, 不修改授权绑定, 不接纳 Operation 或 Attempt, 不代表 Worker 在线, 也不改变静态调度或收录的 Report.

远端启动公告与接收 Attempt 并行, 等待订阅及发送共用 10 秒预算, 不重投原公告. 发布成功也没有 Authority 收录确认; Authority 缺席或公告丢失时, Worker 仍可接收已配置 Authority 的 Attempt. 当前没有观察查询 API, 无跨重启保留; 重启后角色实例仍须由部署方更换. 旧 CLI 演示模式尚不发送公告或心跳.

配置模式的 Worker 每 1 秒发布一次 `kind: "worker_heartbeat"` 消息, 复用相同路由及完整实例绑定字段, 另带从 1 开始的递增 `sequence: u64`. 心跳必须携带非零序号, 启动公告不能携带序号. 两类消息都限制为 4096 字节, 严格校验版本与字段. 心跳自身包含绑定, 所以首次有效心跳也可为已配置的运行实例建立观察, 不要求启动公告先到达. 这不允许新增受信实例或替换已记录的归属.

远端心跳, 一次性启动公告和业务驱动并行, 心跳每次发送最多等待 500 毫秒, 超时不保存或积压旧心跳, 仅记录发布故障的状态变化. 每个 Worker 稳态最多一个心跳发送在途; 计时器跳过错过的周期, 不补发历史周期. 下次周期使用新序号, 不是重试 Operation, Attempt 或 Report. 发送超时或取消不证明底层消息绝不送达. 序号耗尽时停止驱动, 不回绕复用.

Authority 使用本地单调时钟记录收到有效递增序号的时间, 每 250 毫秒检查一次. 初始状态为未观察, 自建立观察槽位或最近有效心跳起 4 秒未见新心跳时转为可疑. 收到有效递增序号后转为在线. 重复或倒序心跳, 重复启动公告和非法消息均不刷新计时, 也不能把可疑恢复为在线. 超时不是硬实时保证, 还受进程调度影响. 仅状态转换写日志, 不为每份正常心跳打印日志.

同 Node 的 Worker 由组合任务每秒直接交付类型化心跳, 无网络或 JSON, 网络消息不得修改本地 Worker 的观察. 本地心跳反映组合任务活动, 远端心跳反映近期收到了发布任务的消息; 两者均不证明执行器可用, 任务有进展或外部效果完成. 心跳没有认证, 仍限受信测试网络; 递增序号只是本次观察中的去重与顺序判断, 不能防止伪造或证明消息新鲜度. 延迟到达的递增消息仍可能刷新观察, 不依赖远端墙钟判断时间.

心跳不改变静态轮转调度, 可疑 Worker 仍可能被选中, 相关 Operation 保持原有等待和 Pending 语义. 心跳超时不删除绑定, Attempt 或 Report, 不证明执行停止或无效果, 不自动创建新 Attempt 或改派. Draining 和退出通知尚未实现.

## 本批实现状态

已实现:

- JSON 配置将 listen/connect 与角色配置分开. 每个 Node 一个共享 Zenoh peer 会话, 角色各自有界订阅. 可以仅承载消息连接, 不配置业务角色.
- 一个 Node 可有多个 Authority 和 Worker, 当前最多 64 个角色. 同 Node 的绑定 Worker 由所属 Authority 组合驱动, 类型化直接交付; 独立 Worker 接收远端授权.
- Console 新增 --authority UUID 定向选择配置模式的 Authority, 不再让多个 Authority 收到同一提交. 旧单 Authority 演示命令保持兼容.
- 64 KiB 配置读取上限, 严格未知字段检查, 重复角色身份和冲突本地绑定在建连前拒绝.

- 配置模式提供有界 Worker 启动公告, 实例归属及心跳在线/可疑观察; 本地类型化记录, 远端独立订阅, 不影响业务执行语义.
- 纯 Kernel 定义独立的 Node/Authority/Worker 稳定与运行身份类型, 领域交付只绑定 RoleInstanceId. 组合配置区分稳定 id 与角色运行 instance; Node 每次启动生成新运行 ID. Worker 命名迁移已完成.

未实现, 不应由上述目标推断已经具备:

- 角色运行 ID 的自动生成与公告驱动的实例解析, 稳定逻辑身份路由; 旧 CLI 演示不提供完整的稳定身份配置.
- Draining 与退出通知; 当前 Ctrl-C 仍退出易失驱动, 无暂停恢复保证.
- Authority 生成 OperationId, SubmissionKey 与独立 Client SDK. 当前演示仍使用 Console 提供的 OperationId.
- 接纳回执与确认重投, 跨重启持久化, 在线调度与动态信任注册.

后续按身份及命名, 生命周期, 有限确认交付, Client 契约逐批实现. 不把未来目标混入当前交付保证.

## 配置示例

同 Node 两个 Authority, 各自绑定一个本地 Worker, 共享监听会话:

```json
{
  "node_id": "00000000-0000-0000-0000-000000001000",
  "listen": ["tcp/127.0.0.1:7447"],
  "connect": [],
  "authorities": [
    {"id": "00000000-0000-0000-0000-000000001100", "instance": "00000000-0000-0000-0000-000000000100", "workers": ["00000000-0000-0000-0000-000000000201"]},
    {"id": "00000000-0000-0000-0000-000000001101", "instance": "00000000-0000-0000-0000-000000000101", "workers": ["00000000-0000-0000-0000-000000000202"]}
  ],
  "workers": [
    {"id": "00000000-0000-0000-0000-000000001201", "instance": "00000000-0000-0000-0000-000000000201", "authority": "00000000-0000-0000-0000-000000000100"},
    {"id": "00000000-0000-0000-0000-000000001202", "instance": "00000000-0000-0000-0000-000000000202", "authority": "00000000-0000-0000-0000-000000000101"}
  ]
}
```

以 `beamlet-node --config PATH.json` 启动. 仓库提供可直接运行的 [组合配置](../../app/beamlet-node/examples/composed.json):

```bash
cargo run -p beamlet-node --offline --locked -- --config app/beamlet-node/examples/composed.json
```

另一终端提交:

```bash
cargo run -p beamlet-console --offline --locked -- \
  --authority 00000000-0000-0000-0000-000000000100 --message hello
```

替换目标末尾的 `100` 为 `101`, 可提交给另一个 Authority. 示例运行身份只用于一轮全新部署, 重新部署须整体一致替换.

反向拓扑: Worker-only 配置 listen 和 workers, Authority-only 配置 connect 和 authorities. Console 可连接 Worker 的监听地址并通过 --authority 指向远端 Authority. 监听不改变授权归属.
