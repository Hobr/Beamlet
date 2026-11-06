# Node 与角色组合

## 已确认的目标

Node 是组合与生命周期容器, 不是业务执行角色. Client 提交意图和读取结果, Authority 持有权威 Operation 记录并授权, Worker 接纳授权并执行. Runner 可指 Worker 内部的执行机制, 不作为对外角色名. 旧代码中的 Work 名称将分批迁移, 不表示另一种角色.

消息会话, 网络监听与连接, 遥测导出, 生命周期管理及未来存储是 Node 基础设施. 它们独立于业务角色配置. 内嵌消息会话不等于内嵌 broker/router; 遥测 exporter 不等于 collector. 当前不新增遥测平台或通用插件框架. 多个角色可共享消息会话, 但不共享授权权力或账本.

同 Node 的绑定角色使用类型化交付, 保留接纳与证据校验步骤, 不绕网络或 JSON. 跨 Node 通过 Adapter 编码交付. 连接必须实际提供路由可达性, 不承诺任意拓扑天然互通.

## 身份与请求

目标稳定身份为 NodeId, AuthorityId, WorkerId; 每次启动独立生成 NodeInstanceId, AuthorityInstanceId, WorkerInstanceId. 角色重启不得复用旧运行身份. 公告与心跳只表达观察, 不自动建立信任或授权.

目标由 Authority 在接纳提交时创建 OperationId. Client SDK 自动创建 SubmissionKey; 同一 Authority 内同键同定义返回原 Operation, 同键不同定义冲突. 去重映射和 Operation 必须作为一次本地接纳建立. 相同意图的新提交仍是新 Operation. Console 不组装底层授权和信封; SDK 暂时只提供 Zenoh, 未来可替换为 socket/HTTP. SDK 丢失提交键及 Operation 引用后, 本阶段不保证恢复请求.

多个独立 Authority 管理不同 Operation. Client 显式选择目标, 查询引用保留归属, 不广播提交. 共享连接不代表共享 Operation 命名所有权或允许自动接管. 当前每个 Worker 绑定一个 Authority, 多 Authority 信任列表另行实现.

当前实际生成仅需要 UUID v4 与 serde, 移除未使用的 v5/v7 features. Kernel 保持不依赖 UUID 生成库.

## 生命周期与交付

目标流程为启动依赖, 启动角色并公告, 心跳观察; 退出时进入 Draining, 停止新接纳, 协作停止或等待在途工作, 保留和交付证据, 发布退出通知, 最后关闭网络及遥测. 退出只移除运行实例的可调度资格, 不删除授权与报告历史. 旧实例的退出通知不得移除新实例.

未开始任务可拒绝并注明 NodeShutdown, Effect::None. 已开始任务需要真实停止或完成证据. 不可确认的执行或外部效果保持未知; 关闭节点不自动证明普通失败或无效果. 不提供任意 future 的暂停恢复, 持久化记录不等于 checkpoint. 迟到证据必须保留.

本阶段后续交付目标为有界, 纯内存的确认与重投: Attempt 接纳回执和 Report 保留回执分开; 先接纳/保留, 后确认; 重复消息重复确认, 不重复执行. 重投复用原身份和内容. 限制队列, 次数, 退避和截止时间. 达到上限保留未确认状态, 不重建授权或自动改派. 有限重试不保证任意故障下最终交付, 也不解决跨重启或效果恰好一次.

## 本批实现状态

已实现:

- JSON 配置将 listen/connect 与角色配置分开. 每个 Node 一个共享 Zenoh peer 会话, 角色各自有界订阅. 可以仅承载消息连接, 不配置业务角色.
- 一个 Node 可有多个 Authority 和 Worker, 当前最多 64 个角色. 同 Node 的绑定 Worker 由所属 Authority 组合驱动, 类型化直接交付; 独立 Worker 接收远端授权.
- Console 新增 --authority UUID 定向选择配置模式的 Authority, 不再让多个 Authority 收到同一提交. 旧单 Authority 演示命令保持兼容.
- 64 KiB 配置读取上限, 严格未知字段检查, 重复角色身份和冲突本地绑定在建连前拒绝.

未实现, 不应由上述目标推断已经具备:

- 稳定/运行身份分层, 代码 Work 到 Worker 的全面重命名.
- 公告, 心跳, Draining 与退出通知; 当前 Ctrl-C 仍退出易失驱动, 无暂停恢复保证.
- Authority 生成 OperationId, SubmissionKey 与独立 Client SDK. 当前演示仍使用 Console 提供的 OperationId.
- 接纳回执与确认重投, 跨重启持久化, 在线调度与动态信任注册.

后续按身份及命名, 生命周期, 有限确认交付, Client 契约逐批实现. 不把未来目标混入当前交付保证.

## 配置示例

同 Node 两个 Authority, 各自绑定一个本地 Worker, 共享监听会话:

```json
{
  "listen": ["tcp/127.0.0.1:7447"],
  "connect": [],
  "authorities": [
    {"instance": "00000000-0000-0000-0000-000000000100", "workers": ["00000000-0000-0000-0000-000000000201"]},
    {"instance": "00000000-0000-0000-0000-000000000101", "workers": ["00000000-0000-0000-0000-000000000202"]}
  ],
  "workers": [
    {"instance": "00000000-0000-0000-0000-000000000201", "authority": "00000000-0000-0000-0000-000000000100"},
    {"instance": "00000000-0000-0000-0000-000000000202", "authority": "00000000-0000-0000-0000-000000000101"}
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
