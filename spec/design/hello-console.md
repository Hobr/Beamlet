# Hello Console 执行演示

Node 组合模式已支持共享消息会话及多个 Authority/Worker, 见 [Node 与角色组合](node-composition.md). 本页下文保留旧 CLI 的单 Authority 演示; 它不代表组合模式的拓扑限制. 执行角色已统一命名为 Worker, Rust 接口与授权消息地址同步采用该名称.

当前里程碑: Console 经 Zenoh 提交 Operation, Authority 授权, Worker 实际调用 `hello()` 返回 `"World"`, Authority 收录 Report 后向提交方返回证据副本. Node 支持本地组合模式, 也支持独立 Authority/Worker 进程.

这不是原样回显, 也不是 Durable 执行系统. 两种模式均只保留内存状态. 固定演示编码位于 Agent 的可选 `test-support` 下, 不属于通用 Agent 契约.

## 运行

无配置路径时启动默认配置: 1 个 Authority 和 1 个本地 Worker. 默认配置与文件配置共用同一个 `run` 入口, 不再区分 `run_local`:

```bash
cargo run -p beamlet-node --offline --locked
```

在另一个终端提交固定 Hello 请求:

```bash
cargo run -p beamlet-console --offline --locked -- --message hello
```

默认入口同样支持角色生命周期订阅, 不必先编写配置或指定 Authority:

```bash
# 终端 A
just node
```

```bash
# 终端 B
just console --subscribe
```

Console 可看到本地 Authority 和 Worker 的启动通知. 保持 Console 运行, 在 Node 终端按 Ctrl-C, 可观察到这两个角色的退出通知. 通知尽力发送, 不承诺强杀时可达; `已发布` 日志不等于 Client 已收到. 默认配置与文件配置使用同一套共享会话, 公共通知及 Draining 协调流程, 同 Node 的执行交付仍为类型化交付. `--listen` 可覆盖默认监听地址, `--role local` 仅为兼容参数. 显式配置文件无法读取或内容无效时直接报错, 不静默回退默认配置. 本次逻辑身份和运行实例均随机生成, 不跨启动保留; 需要固定逻辑身份时使用配置模式. 显式旧独立 `--role authority`/`--role worker` CLI 暂不提供公共通知.

也可直接启动 Console, 输入 `hello` 后按 Enter. 每条输入创建新的 Operation; 相同任务不代表相同请求. 不再将任意输入文本回显为结果. `Hello` 大小写兼容.

正常输出包含:

```text
Operation: <OperationId>
Attempt: <AttemptId>
Report: <ReportId>
状态: 成功; Effect: None
输出: "World"
```

程序自有的日志, 帮助和错误提示使用中文说明, Operation, Attempt, Report, Authority, Worker, Node, Console, Effect 等领域名词及枚举标识保留原文. CLI 参数, JSON 字段与协议标识保持不变; 第三方库及系统原始诊断不承诺中文化. 日志文本不是机器交互协议.

`Effect::None` 来自该固定函数不执行外部效果, 不是从成功状态推导出的结论.

### 重复提交

Node 保持运行, 在两个终端使用同一个 Operation ID:

```bash
cargo run -p beamlet-console --offline --locked -- \
  --message hello --operation-id 00000000-0000-0000-0000-000000000001
```

两次返回应具有相同的 Attempt ID 和 Report ID; Node 的 `Worker 已执行 hello` 日志对该 Operation 只出现一次. `--operation-id` 仅适用于 `--message hello`, 不会变成交互模式中所有输入共享的身份.

多个 Console 仍各自使用随机会话回复地址. Console 会话 ID 与 Operation ID 独立; 同一 Operation 可通过新的 Console 会话再次提交并读取原有证据. 路由 ID 不是认证凭证.

原有单进程混合假任务演示保留在两个程序的 `--demo` 参数下.

## 独立 Authority/Worker 进程

以下命令使用同一个静态 TCP 连接地址, 不需要另行启动 zenohd. 该网络只运行一个 Authority; Console 不需要知道 Worker 的地址或身份.

示例 UUID 只适用于一轮全新的部署. 实例 UUID 不是稳定节点名: 重启整组进程时必须生成三个新 UUID 并一致替换所有命令中的对应值. 当前不支持单个 Worker 重启后复用旧实例身份, 也不支持在线修改静态 Worker 列表. 身份绑定不等于网络认证.

1. 终端 A 启动 Authority, 显式配置两个 Worker 实例:

   ```bash
   cargo run -p beamlet-node --offline --locked -- \
     --role authority --listen tcp/127.0.0.1:7447 \
     --instance 00000000-0000-0000-0000-000000000100 \
     --worker 00000000-0000-0000-0000-000000000201 \
     --worker 00000000-0000-0000-0000-000000000202
   ```

2. 终端 B 启动第一个 Worker:

   ```bash
   cargo run -p beamlet-node --offline --locked -- \
     --role worker --connect tcp/127.0.0.1:7447 \
     --instance 00000000-0000-0000-0000-000000000201 \
     --authority 00000000-0000-0000-0000-000000000100
   ```

3. 终端 C 启动第二个 Worker:

   ```bash
   cargo run -p beamlet-node --offline --locked -- \
     --role worker --connect tcp/127.0.0.1:7447 \
     --instance 00000000-0000-0000-0000-000000000202 \
     --authority 00000000-0000-0000-0000-000000000100
   ```

4. 终端 D 启动 Console, 连续输入 `hello`:

   ```bash
   cargo run -p beamlet-console --offline --locked
   ```

新 Operation 按静态列表轮转, 两个 Worker 终端应分别出现 `Worker 已执行 hello` 日志. 使用上面的 `--operation-id` 命令重复提交时, 应复用原有 Attempt 和 Report, 不新增执行日志. 也可以仅配置一个 `--worker` 运行最小的三进程闭环.

停止一个 Worker 不会触发故障转移: 分配给它的请求保持待定, 不自动改派另一个 Worker. 分配给仍运行 Worker 的新请求仍可完成. 若原始派发尚在等待订阅就绪, Worker 在该次 10 秒发送等待结束前首次连接, 原消息仍可能被交付; 这是同一次发送, 不是自动重投.

## 处理路径

本地组合与分进程模式复用独立 Authority/Worker 驱动; 本地组合直接进行类型化交付, 不强制序列化或回环网络:

1. Console 生成或读取稳定 Operation ID, 将固定 Hello 请求编码一次.
2. Authority 在接纳前检查消息大小, 严格 JSON 字段, 协议版本和固定任务种类.
3. `Authority::submit` 保留授权, 只有新接纳请求才向指定 Worker 发送原始 DispatchAttempt. 发送确认单独记录, 不代表 Worker 接纳.
4. `Worker::receive_dispatch` 检查实例及授权绑定; `Worker::next_report` 执行普通 `hello()` 函数, 缓存 Report 后尝试发送. Authority 通过 `receive_report` 校验并收录证据.
5. Authority 向等待的 Console 专用地址发送已收录的证据副本. 交付失败不移除已保留的结果, 也不自动重新执行.

已完成 Operation 的重复提交直接读取原有 Report, 不生成第二次执行. 仍无证据的原有请求返回 Pending, 不自动重新派发或创建新 Attempt. 预期的提交错误独立于执行 Report 返回, 并附带当前保留状态; Worker 拒绝入队时 Authority 可能已经接纳. 驱动或内部状态错误停止 Node, 不伪造普通失败证据.

## 编码与边界

共享编码实现: [Agent Hello 演示编码](../../agent/beamlet-agent/src/testing/hello.rs).

Console 请求是当前 Node 连接上的固定演示包装:

```json
{
  "protocol_version": 0,
  "operation_id": "00000000-0000-0000-0000-000000000001",
  "task": "hello"
}
```

响应包装区分 `report`, `pending`, `submission_error`. `report` 包装的是已有 [v0 协议](volatile-protocol.md) 的 Worker-to-Authority `SubmitReport` 信封副本, 保留原始实例绑定及 Operation/Attempt/Report 身份. 不会把原信封的目标实例改写成 Console, 也没有为既有三种业务消息添加通用查询或能力注册协议.

跨进程 DispatchAttempt 使用同一 Hello 演示模块中的严格 `Dispatch` 编码, 携带源/目标实例, 原有 Attempt ID 及完整固定 Operation. Worker 的 SubmitReport 使用已有 v0 信封编码. Authority 的报告地址为 `beamlet/v0/node/inbox/reports-<authority-id>`, Worker 的授权地址为 `beamlet/v0/worker/<worker-id>/inbox`; 地址中的实例 ID 使用 32 位十六进制表示. Console 的现有请求/响应编码和专用回复地址保持不变. 没有新增业务消息种类, 能力注册或通用消息总线.

当前请求, 跨进程授权, Report 及完整 Console 响应包装分别受 64 KiB 应用消息预算限制. Authority 默认保留 1024 个 Operation, 满后拒绝新的身份, 不淘汰旧记录来重新执行. 每个 Worker 的记录同样受限. 本地模式及每个 Worker 当前逐条执行 Hello, 不承诺慢任务之间的公平性或并行调度.

分进程 Authority 的等待回复记录和后台发送任务各自最多 256 个. 添加后台发送任务前检查上限, 避免离线 Worker 或消失的 Console 阻塞接收循环. 等待记录满时返回独立提交错误; 发送任务已满时不再提交本次请求, Console 可能等待超时. 两者均不生成失败 Report 或新授权. 这些应用上限不涵盖 Zenoh 自身所有内部缓冲区.

分进程 Authority 等待约 5 秒仍无 Report 时, 准备返回 Pending 并释放本次等待记录, 不取消执行或结束原有发送等待. 网络发送各自最多等待 10 秒; 背压或发送任务占满时不保证 Pending 在 Console 截止时间前送达. 没有 Console 等待时收到的迟到 Report 仍被收录, 后续使用原 Operation ID 可读取该证据.

Console 的 10 秒结果等待超时不取消 Worker, 不证明未接纳或没有效果, 不自动重新提交. 有需要时可在同一仍运行的 Authority 上使用原 Operation ID 再次提交. 尚未完成请求的重复提交不会自动重发原 DispatchAttempt; Report 发送失败也不会自动重投, 即使 Worker 缓存仍在. 本轮没有可靠交付保证.

Authority 重启会丢失全部请求和收录证据; Worker 重启会丢失其执行记录和报告缓存. 原 Operation ID 不提供跨重启去重或恢复保证. 此里程碑不包含持久化, Outbox, 自动重投, 身份认证, 能力注册, 真实 Tool 或 LLM.

## 接收路径选择

当前环境启用 Zenoh 1.10.2 的 `uring` 功能时, 连续创建 Console 连接会复现订阅就绪超时: 会话已连接, 但匹配状态仍为 false. 延长等待或重新发送 Operation 不能作为修复.

工作区当前不启用 `uring`, 使用 Tokio TCP 接收路径. 同环境关闭后的反复建连对照已通过, 不代表其他平台上的 io_uring 都有问题, 也不是上游根因证明. 再次启用前应重新验证多连接创建与销毁. 未更换 peer/client 拓扑, 未延长超时, 未加入自动重发.
