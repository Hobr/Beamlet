# Actions：中立操作契约

此库定义不可执行的 Operation 描述、一次尝试的 Execution、已准入的 ExecutionHandle、瞬时 OperationRef、单次终态 Result，以及本地 Handler 行为。它不提供调度、存储、重试或进程监督；这些职责分别属于 Runtime 与领域存储。无兄弟应用或第三方依赖，使用 OTP JSON 校验专用凭据，无 Application 启动回调。

在仓库根目录使用 `nix develop` 进入 OTP 29 / Elixir 1.20 环境，首次执行 `mix deps.get`，再运行 `iex -S mix`。无需数据库、模型认证或 Node 即可构造和校验数据：

```elixir
alias Beamlet.Actions.{Operation, Result}
{:ok, operation} = Operation.new(kind: "echo", payload: %{"text" => "你好"}, budget_ms: 1000)
:ok = Operation.validate(operation)
true = Result.valid?(%Result{
  operation_id: "op-1", execution_id: "exec-1", source: :execution,
  status: :ok, value: %{"text" => "你好"}
})
```

Operation 的 kind、能力、环境标签均为不透明数据，不解析成代码；有效描述也不保证目标存在或资源获准。预算为 1..3600000 毫秒，能力最多 32 项、节点最多 64 项，claims 为最多 32 个正数资源声明。普通字段以及含 credentials 的整个结构各受 262144 字节 Erlang 外部序列化限制。

普通数据可为原子、数值、UTF-8 字符串、列表或普通 map，最大深度 24；拒绝结构体、函数、PID、引用、元组及预定义敏感键。这是结构策略，不是对文本内容的脱敏保证。metadata 可以是标量或列表。`bounded?/2` 使用 Erlang 大小，不能与 Harness 的 JSON 字节限制互换。

专用 credentials 默认 `%{}`，只接受字符串键 JSON 对象，完整 JSON 最多 16384 字节，顶层最多 32 个键，键名 1..128 字节，递归深度 24。递归拒绝大小写不敏感的 root/workspace_root，但允许 api_key/token 等凭据字段。不得将其复制到 payload、metadata、进度、Result 或诊断。

Result 整体和普通字段均最多 1 MiB，metadata 必须为普通 map；执行侧来源必须包含 execution_id。`uncertain` 仅是观察，不能证明远端已停止或自动授权重试。OperationRef、ExecutionHandle 含本地运行身份，不能持久化重放。Handler 的 settings、remaining_ms、progress 与 cancelled? 是执行器本地上下文，返回值仍需 Result 校验；进度可能因信用额度返回 `progress_limit`。

在仓库根目录验证：

```sh
mix test --no-start apps/beamlet_actions/test --seed 631927
elixir scripts/quality/check-contracts.exs
```
