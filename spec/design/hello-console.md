# Hello Console 执行演示

当前里程碑: Console 经 Zenoh 提交 Operation, 单个 Node 在内存中组合现有 Authority/Work, Work 实际调用 `hello()` 返回 `"World"`, Authority 收录 Report 后向提交方返回证据副本.

这不是原样回显, 也不是独立 Work 进程或 Durable 执行系统. 固定演示编码位于 Agent 的可选 `test-support` 下, 不属于通用 Agent 契约.

## 运行

启动 Node:

```bash
cargo run -p beamlet-node --offline --locked
```

在另一个终端提交固定 Hello 请求:

```bash
cargo run -p beamlet-console --offline --locked -- --message hello
```

也可直接启动 Console, 输入 `hello` 后按 Enter. 每条输入创建新的 Operation; 相同任务不代表相同请求. 不再将任意输入文本回显为结果. `Hello` 大小写兼容.

正常输出包含:

```text
operation: <operation-id>
attempt: <attempt-id>
report: <report-id>
status: succeeded; effect: None
output: "World"
```

`Effect::None` 来自该固定函数不执行外部效果, 不是从成功状态推导出的结论.

### 重复提交

Node 保持运行, 在两个终端使用同一个 Operation ID:

```bash
cargo run -p beamlet-console --offline --locked -- \
  --message hello --operation-id 00000000-0000-0000-0000-000000000001
```

两次返回应具有相同的 Attempt ID 和 Report ID; Node 的 `work executed hello` 日志对该 Operation 只出现一次. `--operation-id` 仅适用于 `--message hello`, 不会变成交互模式中所有输入共享的身份.

多个 Console 仍各自使用随机会话回复地址. Console 会话 ID 与 Operation ID 独立; 同一 Operation 可通过新的 Console 会话再次提交并读取原有证据. 路由 ID 不是认证凭证.

原有单进程混合假任务演示保留在两个程序的 `--demo` 参数下.

## 处理路径

1. Console 生成或读取稳定 Operation ID, 将固定 Hello 请求编码一次.
2. Node 在接纳前检查消息大小, 严格 JSON 字段, 协议版本和固定任务种类.
3. Node 调用现有 `Agent::submit`, Authority 保留授权, Work 在本地接纳原始 Attempt.
4. Node 调用 `Agent::next_report`, Work 执行普通 `hello()` 函数, 缓存 Report, Authority 收录该证据.
5. Node 尝试向当前提交方的专用回复地址发送证据副本. 交付失败不移除已保留的结果, 也不自动重新执行.

已完成 Operation 的重复提交直接读取原有 Report, 不生成第二次执行. 仍无证据的原有请求返回 Pending, 不自动重新派发或创建新 Attempt. 预期的提交错误独立于执行 Report 返回, 并附带当前保留状态; Work 拒绝入队时 Authority 可能已经接纳. 驱动或内部状态错误停止 Node, 不伪造普通失败证据.

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

响应包装区分 `report`, `pending`, `submission_error`. `report` 包装的是已有 [v0 协议](volatile-protocol.md) 的 Work-to-Authority `SubmitReport` 信封副本, 保留原始实例绑定及 Operation/Attempt/Report 身份. 不会把原信封的目标实例改写成 Console, 也没有为既有三种业务消息添加通用查询或能力注册协议.

当前请求大小与完整响应包装均受 64 KiB 应用消息预算限制. Node 默认保留 1024 个 Operation, 满后拒绝新的身份, 不淘汰旧记录来重新执行. Hello 当前逐条处理, 不承诺慢任务之间的公平性或并行调度; 没有新增无限队列或 Console 路由记录表.

Console 的 10 秒结果等待超时不取消 Work, 不证明未接纳或没有效果, 不自动重新提交. 有需要时可在同一仍运行的 Node 上使用原 Operation ID 再次提交. Node 重启会丢失全部内存证据; 原 ID 不提供跨重启去重或恢复保证.

此里程碑不包含独立 Work 进程, 持久化, Outbox, 自动重投, 身份认证, 能力注册, 真实 Tool 或 LLM.

## 接收路径选择

当前环境启用 Zenoh 1.10.2 的 `uring` 功能时, 连续创建 Console 连接会复现订阅就绪超时: 会话已连接, 但匹配状态仍为 false. 延长等待或重新发送 Operation 不能作为修复.

工作区当前不启用 `uring`, 使用 Tokio TCP 接收路径. 同环境关闭后的反复建连对照已通过, 不代表其他平台上的 io_uring 都有问题, 也不是上游根因证明. 再次启用前应重新验证多连接创建与销毁. 未更换 peer/client 拓扑, 未延长超时, 未加入自动重发.
