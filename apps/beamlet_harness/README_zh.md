# Harness：原生模型与工具边界

Harness 定义独立的 Model、Tool、Context、Environment 契约，以及纯目录/schema/历史校验。它直接依赖 Req **0.7.5** 与 Jason，不依赖 Actions、Runtime、Agent 或 Phoenix；无 Application 回调，不自动启动执行器。模型配置与 credentials 显式传入，工具 root/settings 由受信本地组合层解析，不能放入目录。Environment 只承载不透明 id。

在仓库根目录进入 `nix develop`（OTP 29 / Elixir 1.20），首次 `mix deps.get`，使用 `iex -S mix` 调用。下面无需服务、网络、认证或工作区：

```elixir
alias Beamlet.Harness.{Catalogue, Context, Model}
alias Beamlet.Harness.Models.Deterministic
alias Beamlet.Harness.Tools.Deterministic, as: Echo
{:ok, catalogue} = Catalogue.new([Echo.descriptor()])
{:ok, [%{id: "call-1"}]} = Catalogue.batch([
  %{"id" => "call-1", "name" => "echo", "arguments" => %{"text" => "你好"}}
], catalogue)
{:ok, %{text: "你好"}} = Echo.invoke(%{"text" => "你好"}, %{})
request = %{messages: [%{"role" => "user", "content" => "你好"}], catalogue: catalogue}
invocation = %{
  config: %{"reply" => %{"kind" => "text", "content" => "完成", "calls" => []}},
  credentials: %{}
}
:ok = Model.validate_request(request)
{:ok, reply} = Deterministic.complete(request, invocation, %Context{})
:ok = Model.validate_reply(reply, catalogue)
%{"role" => "assistant", "content" => "完成"} = Model.assistant_message(reply)
```

Model 的 `validate_invocation/1` 必须纯校验；`complete/3` 返回中立 reply 或安全原子错误，直接调用也要校验请求。通用 invocation 恰含 config/credentials，各为不超过 16 KiB 的字符串键 JSON 对象、深度最多 24。config 递归拒绝敏感/根目录标签；credentials 最多 32 个顶层键，键名 1..128 字节，递归拒绝大小写不敏感的 root/workspace_root。适配器另检查自己的必填字段。注册表最多 32 个受信本地模块，ID 只能是 1..64 个 ASCII 字母、数字、下划线或连字符；便携 ID 不转为代码或原子。

Tool 的 `descriptor/0` 只返回 name/description/parameters 数据；`invoke/3` 使用已解码参数、本地设置与 Context。Catalogue 最多 64 个描述，每个完整 JSON 最多 16 KiB、description 最多 4096 字节。schema 只支持浅层 object 中的 string/integer/number/boolean、enum、字符串长度和数值边界；不支持数组、嵌套 schema、refs、pattern 或 union。字符串长度按码点计，默认上限 16384；额外属性默认禁止，显式允许时只能是 JSON 原始值。schema 校验不保证检查出所有不可满足的边界组合。

`Catalogue.batch/2` 接收字符串键 id/name/arguments，必须为 1..8 个完整调用，ID 唯一且为 1..128 字节 UTF-8，参数各最多 16 KiB。成功返回原子键调用并保留顺序；任一失败整批失败，目录不执行工具。并行执行由宿主负责，结果须按原 ID 顺序归并。规范 assistant 工具消息使用 calls，tool 观察使用 call_id；必须全部有序配对后才能继续模型步骤，不接受供应商 wire envelope 或 JSON 字符串参数。

Context 消息最多 128 条且整体 JSON 最多 1 MiB，追加超限拒绝，不驱逐历史；完整请求、传入/归一化回复、HTTP 请求/响应分别受 1 MiB 限制。进度事件最多 8192 字节 JSON；无钩子时 emit 直接成功，有钩子时返回其原值。钩子是受信本地代码，取消在调用前检查，阻塞 I/O 的整体期限与生命周期由 Runtime 等宿主处理。字节上限不是硬 RSS 或解析深度保证；Actions 的 Operation 上限还可能更小，不能截断参数来适配。

OpenAICompatible 只支持非流式文本 Chat Completions（n=1、stream=false）。config 要求 base_url/model，可选 timeout_ms（默认 5000，1..60000）和 allow_local_http（默认 false）；credentials 恰含 api_key（1..4096 字节 UTF-8，无 CR/LF）。不读环境变量，不支持任意 Req/TLS 参数或额外生成参数。HTTPS 校验对端；开发 HTTP 必须显式启用且只允许 localhost/127.0.0.1/::1。base path 后追加 `/chat/completions`，禁止 userinfo/query/fragment。不重试、不重定向、不回退；只接受一个 choice、受支持字段及完整 stop/tool_calls，拒绝 refusal/length/content_filter。超时或本地进程停止不证明上游取消或无计费。错误为安全标签，不应记录原始 body、提示、凭据或根路径。

WorkspaceRead 的 descriptor 无需文件系统；实际调用须预先配置受信的本地绝对 root，可选 max_bytes（默认/上限 65536）。参数只含相对 path，最多 4096 字节、32 段；拒绝空段、点段、反斜杠、NUL、符号链接、非目录中间项和非普通文件。读取 max+1 哨兵并始终关闭描述符，返回 text/bytes/truncated；截断可去掉不完整 UTF-8 码点，但不会扫描更远内容。路径/设置失败为 workspace_unavailable，观察到非法 UTF-8 为 invalid_utf8。逐级 lstat/open/fstat **不是原子 OS 隔离**：TOCTOU、竞态 FIFO、硬链接、挂载、特权写入、非快照内容和存储阻塞仍可能存在。须控制祖先及写入者，优先使用 OS 只读树；没有 shell、写入、目录列举或回退 root。

在仓库根目录验证：

```sh
mix test apps/beamlet_harness/test --seed 631927
elixir scripts/quality/check-contracts.exs
```

HTTP/工作区测试使用真实本地 TCP/TLS、OpenSSL、mkfifo 和 Linux `/proc/self/fd`；缺少前提不能记作通过。它们不证明付费提供者或物理跨机部署可用。
