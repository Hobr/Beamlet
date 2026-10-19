# Server 部署与验收

[English](README.md)

两个独立宿主是 `beamlet_app_server`（`Beamlet.Server`）与 `beamlet_app_web`（`Beamlet.Web`）；其余 OTP 应用保持可嵌入的能力。

> 证据边界：本页描述仓库内的构建/检查脚本能做什么。本次文档工作没有执行部署、发布打包或跨机验收；`check-release.sh`、`check-local.sh` 只在同一台机器上对复制出的产物做检查，**不构成**物理部署、断电、付费模型或真实集群验收。

## 破坏性迁移

| 旧 | 新 |
| --- | --- |
| `apps/beamlet_daemon`、`:beamlet_daemon` | `apps/beamlet_app_server`、`:beamlet_app_server` |
| `Beamlet.Daemon` 及其子模块 | `Beamlet.Server` 及其子模块 |
| `apps/beamlet_web`、`:beamlet_web` | `apps/beamlet_app_web`、`:beamlet_app_web` |
| `bin/beamlet_daemon` | `bin/beamlet_server` |
| `daemon.example.exs` | `server.example.exs` |

升级时同步更新配置命名空间与服务命令，并用匹配的配置部署重新构建的完整产物。仓库不提供旧别名、转发模块或配置回退。Web release 名仍是 `beamlet_web`，其模块命名空间、会话 cookie 与 salt 保持不变；CLI 命名不变。不带名称的 `mix release` 现在选择 `beamlet_server`，`mix release beamlet_daemon` 不再受支持。

## 一个产物，三种启动配置

从检出目录用项目自带 OTP/Elixir 工具链构建：

```sh
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_server --overwrite
bash scripts/deployment/check-release.sh
```

后端选择器包含两个持久化库并排除 Web，构建落在隔离的 `_build/backend`。每个 release 只含自己的依赖闭包：server 不含 CLI/i18n/Gettext，CLI 不含 server/Web；这也避免 Web 的 Req 可选 Plug 依赖混入后端。三个命名 release 都使用 Mix 自带的 `config/runtime.exs`；server 与 CLI 不需要 Web 密钥。

共享的 `config/config.exs` 导入 dev/test/prod 构建配置。Mix 把那些值嵌入 `sys.config`，并把 `config/runtime.exs` 复制为 `releases/0.1.0/runtime.exs`。运行时配置在应用启动前求值。只有匹配的 `RELEASE_NAME` 才会激活对应宿主；普通源码/库加载保持 opt-in。**每个 VM 只保留一个启用的宿主/Node。**

把 release 目录复制到兼容的操作系统/架构之外的位置。目标机既不需要项目源码也不需要 Mix；但打包的 ERTS 仍需要匹配的系统/原生库。重建曾自定义过的 release 时使用全新输出目录：`--overwrite` 可能残留旧产物（包括已退役的包装脚本/应用）。重建前只删除生成的宿主 release 目录，部署完整的新目录树而不是叠加覆盖。

组装 Web 前先构建资源：

```sh
MIX_ENV=prod mix compile --warnings-as-errors
MIX_ENV=prod mix tailwind beamlet_web --minify
MIX_ENV=prod mix esbuild beamlet_web --minify
MIX_ENV=prod mix phx.digest
MIX_ENV=prod mix release beamlet_web --overwrite
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_cli --overwrite
```

Web 需要安全提供现有 `SECRET_KEY_BASE`，然后运行 `bin/beamlet_web start`；该 release 会启用 Endpoint 服务与 Web 宿主。生产环境从源码启动 Web 仍保留必需的密钥检查。后端 release 不带 Web，也不需要占位密钥。

**不要构建按角色分裂的产物。** [server.example.exs](server.example.exs) 与 [cli.example.exs](cli.example.exs) 里的应用设置示例是供你在共享构建配置或打包的 `runtime.exs` 中改写的片段，不会被自动加载为外部文件。例如：

```elixir
config :beamlet_app_server,
  node: [], # 默认 [:authority, :executor]
  allowed_nodes: ["executor@c.example.internal"],
  peers: ["executor@c.example.internal"]
```

仅权威用 `node: [roles: [:authority]]`，仅执行用 `node: [roles: [:executor]]`。空列表、重复、interaction 与未知角色都会在任何角色启动前被拒绝。只支持这些启动期选择：没有运行时角色切换/重配置 API。两种能力的代码都在每个副本里。Node 仍是内嵌库，覆盖七种角色组合；它不是可执行文件，也不读取应用启动配置。

不存在 Beamlet 外部配置文件约定、发现机制、CLI 配置开关、提供者框架或部署包装脚本；旧的外部文件启动契约已退役。配置/runtime 脚本是以部署用户权限执行的可信 Elixir，不是沙箱：限制其所有权，绝不要喂入模型输出。现有宿主校验器仍会在启动时拒绝非法应用设置；原生脚本的语法/异常诊断不由自定义读取器脱敏。

普通 umbrella 启动是 enabled=false 与空的后台树。启动后修改 Application env 不会重配运行中的宿主。运行时改动需要重启，并且必须能撑过下一次部署；编译期设置（含 `force_ssl`）需要重新构建。不提供热重载或目标机上的编辑接口。

权威启动不需要用户密钥或工作区。在 authority/executor 上用 `model_providers` 注册可信模型适配器（默认：openai-compatible 与 deterministic）。执行器 Tool profile 只含执行器本地设置与根目录；使用有界池与仓库自带 Tool 白名单。Agent 创建时提供一份不可变的 model/provider/config/credentials/placement 绑定。**绝不**在执行器 profile 里静态写入用户模型密钥；也不存在 `key_env` 回退。

## 服务与集群引导

使用原生 Mix Release 默认设置，或其支持的 `RELEASE_NODE`、`RELEASE_COOKIE`、`RELEASE_DISTRIBUTION`、`RELEASE_VM_ARGS`、`RELEASE_REMOTE_VM_ARGS`。没有自定义 shell 要求身份/cookie/配置变量，也不会固定分布端口；请在构建主机上用 `mix help release` 查阅原生设置与可写运行时配置要求。

在 systemd 或容器中前台运行 `bin/beamlet_server start`（需要可信会话时用 `start_iex`）。Unix 上 `bin/beamlet_server daemon` 提供原生后台运行；用原生 `pid`、`rpc`、`stop` 查看与停止。复制产物检查会验证后台启动与真实 VM 退出。原生 `pid`、`rpc`、`remote`、`restart`、`stop` 控制在持有服务身份/cookie 时都可用。原生默认包含构建时生成的 release cookie 与以 release 命名的节点；同时运行多个副本时使用唯一名称，并为可信集群安全地轮换/发放 cookie。不要记录 cookie 或开启 shell tracing。`help` 与 `version` 不需要应用配置或 Web 密钥。

用 `bin/beamlet_server stop` 停止；在认定关闭完成前检查服务管理器与 socket。EPMD TCP4369 与配置/原生分布监听必须可双向可达；如需端口限制，用原生 VM 参数实现，而不是 Beamlet 的固定端口变量。使用可信私有网络/防火墙：cookie 分布等于可信代码执行权限，不是 Internet 或多租户认证。不提供 TLS 部署方案。

allowed_nodes 是受信列表：最多 32 个 ASCII `node@host` 名称，每个最多 255 字节。peers 是它的不同子集，最多 32 项。Node 就绪后，宿主拥有的临时任务用 `Beamlet.Node.Cluster` 顺序地**各连接一次**（每次尝试最多 5 秒）。启动监督不等待网络完成；32 个失败 peer 最坏约需 160 秒耗尽。日志只报告 peer 序号与 connected/unavailable。失败后本地服务继续存活。没有后台重连、扫描、自动发现或业务重试/重放。宿主丢失会清理任务/控制器/辅助进程所有权；OTP 仍可能稍后完成已发起的握手，因此这不是网络回滚。

受信运维者可以显式再次连接，而不重放业务工作：

```elixir
alias Beamlet.Node.Cluster
allowed = ["executor@c.example.internal"]
:ok = Cluster.connect("executor@c.example.internal", allowed)
{:ok, executor} = Cluster.authority("executor@c.example.internal", allowed)
{:ok, nodes} = Cluster.connected(allowed) # 不会隐式建立连接
```

## 确定性模型与 HTTP/Tool 控制

在权威的 IEx 或一个受信 RPC 脚本中（server 打包 Agent API，**不含**终端客户端），先等到符合条件的 Directory 容量报告再输入：

```elixir
{:ok, ref} = Beamlet.Agent.start(node(), id: "operator-demo",
  model: %{provider: "deterministic",
    config: %{"reply" => %{"kind" => "text", "content" => "ok", "calls" => []}},
    placement: %{allowed_nodes: [executor]}})
:ok = Beamlet.Agent.subscribe(ref)
# 接收 {:beamlet_agent, ^ref, sequence, {:snapshot, snapshot}}
# 并从同一 sink 确认每个序号：Beamlet.Agent.ack(ref, sequence)。
{:ok, turn} = Beamlet.Agent.input(ref, "hello")
Beamlet.Agent.snapshot(ref)
Beamlet.Agent.stop_turn(ref)
:ok = Beamlet.Agent.unsubscribe(ref)
Beamlet.Agent.close(ref)
```

订阅后的初始快照先于后续更新到达。sink 丢失/超时不决定 Agent 生命周期；关闭必须显式。不要把活跃 Ref 序列化为持久句柄。发现/重挂与独立 CLI 会话属于 CLI release，不属于 Node 的隐藏可执行依赖。就在同一个运维会话/脚本中保管活跃 Ref。CLI 的库测试夹具存在于仓库，但不会打进 server 产物。

若要做一次不花钱的 HTTP → 工作区 → 模型演练，在执行器上运行保持不变的 `python3 scripts/deployment/http-fixture.py --requests 16`：它监听 loopback TCP18080，请求数上限 16，accept 等待 30 秒、整个请求 10 秒。准备一棵专用的许可标记树，以及带 root/max_bytes、能力、环境与有界原生池的 WorkspaceRead Tool profile。用 WorkspaceRead.descriptor 构建可移植目录，把 workspace_read 路由到该 profile/环境，并把 placement 限制在执行器。Agent 模型绑定使用 provider openai-compatible、配置 `%{"base_url" => "http://127.0.0.1:18080/v1", "model" => "fixture", "allow_local_http" => true}` 与显式合成凭据 `%{"api_key" => "synthetic-fixture-key"}`。Loopback 在选定的执行器上解析。夹具先请求 marker.txt，再报告**完整的 Tool 观察摘要**：把它与预期 Tool JSON 内容的 SHA256 对比。仅有夹具最终字符串不足以证明读到了标记。迁移后的命名 CLI 集成保留真实的 HTTP 授权/正文分离、摘要关联、错误环境不回退、具有新容量后的后续 turn、requests 被挂起期间的 stop，以及执行器丢失/不重放。这些测试/夹具不会访问付费提供者。

授权真实调用时使用显式 Agent 凭据与支持的 HTTPS 文本非流式 Chat Completions/function tools。系统 CA 信任与对端校验仍为强制；不提供自定义 CA/生成覆盖或自动重试。请先取得独立的端点与花费批准。绝不要记录请求、设置、密钥、根目录或原始 provider 异常。凭据在权威与执行器进程/临时消息中是明文，直到常规清理为止；不承诺安全擦除，也不承诺抵御管理员检查或恶意 provider 回显。子 Agent 需要自己的显式绑定，peer 不继承凭据。

工作区检查会拒绝路径穿越/符号链接/非常规文件，并对 UTF-8 读取设上限，但不是原子的操作系统隔离。准备受控祖先目录与后端写入者，最好是操作系统只读。硬链接/挂载/TOCTOU/敌意写入者仍在信任边界之外。等待中的委派父级不占执行器容量。Stop 冻结推进并请求尽力清理；DOWN/分区不证明上游回滚、终止或计费停止。绝不重放不确定的业务工作。

## 检查、证据与回滚

`check-release.sh` 把 server、CLI 与 Web 产物复制到源码/deps 之外，对复制树做指纹，并检查隔离的依赖闭包。它用同一个 server 产物测试默认/仅权威/仅执行三种命名模式、不使用自定义 shell 策略的原生 RPC/pid/stop、失败 peer 的继续、权威到执行器的引导，以及一次确定性远程 Gateway turn。夹具改的是每个副本**打包的 runtime.exs**；没有外部读取器。九个非法宿主选项仍在启动时失败且不泄漏 sentinel，缺失数据集绝不会在启动时被创建。旧读取器路径/语法脱敏测试不再适用于原生可信脚本。既有 Python 清理失败回归保持不变。

CLI 检查保留前台 stdin、quit/EOF 后重挂到完全相同的 Ref、显式关闭、Unicode/身份分页以及真实 PTY 模型输出。Web 检查会拒绝缺失密钥、用原生身份/cookie 默认值启动、从复制并 digest 的产物请求真实 HTTP 与 CSS/JS，并演练原生控制。Web 夹具只改副本的监听端口/IP。不需要仓库内的探测文件或新的部署变量。

把已有的 `BEAMLET_CHECK_LOG_DIR` 设成你想要保留日志的目录；否则脚本会打印并保留一个临时证据目录。需要 Python3.11+、EPMD/本地 socket 与原生系统库。七个库角色组合仍是独立测试，不是 server 启动选项。

`bash scripts/deployment/check-local.sh` 运行格式/编译/umbrella/命名测试、静态分析、三个 release 构建与复制产物检查。**本地检查通过不代表物理部署或验收**。普通与命名分布测试的实际数量、失败日志、活动 LSP 限制与复制哈希都应记录在任务证据里。命名 Mix 测试只使用调度器参数 `ERL_FLAGS='+S 2:2'` 并显式传入安全生成的父 `--cookie`；绝不把 `-setcookie` 放进继承的 ERL_FLAGS（曾观察到父子不匹配）。

物理多主机执行与付费调用**未验证**，这些检查也不授权它们。不执行 SSH/部署。要求构建与协议匹配；回滚使用保留的旧产物**及其匹配的旧配置**，绝不用混合版本集群。重启不是恢复丢失的 Agent/历史。收尾需显式关闭 Agent、停止服务/夹具、核验监听、移走临时许可夹具并吊销任何临时凭据。

## 前台交互 CLI

用 `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_server --overwrite` 与等价的 `mix release beamlet_cli --overwrite` 构建后端。后端编译选择器包含两个宿主；每个 release 的依赖闭包只含自己的宿主并排除 Web。普通 umbrella 加载不启动任何宿主的 Node，也绝不读取 stdin。

把 CLI release 目录复制到检出目录之外。在共享配置或其打包的 runtime.exs 中改写 `cli.example.exs` 的应用设置；可信分布与唯一节点身份使用原生 Release 设置。前台运行 `bin/beamlet_cli start`；stdin 无需 IEx 即可接收命令。`help` 描述语法。依次可用 `connect authority@host`、`agents`、`attach authority@host agent-id local-alias`、`status local-alias`、`input local-alias text`、`watch local-alias 5000 64`、`stop local-alias`、`close local-alias`。`create authority@host /absolute/agent-options.exs` 读取 `:beamlet_cli, :agent_options`；确定性夹具见 `agent-options.example.exs`。真实模型绑定与 Tool 目录/路由使用与 HTTP/工作区集成相同的 Agent 选项，由运维者选择 provider 配置与专用凭据。含凭据的文件只能由运维者访问。配置文件是**可信可执行 Elixir 代码**，绝不是沙箱，也不是模型输入。CLI 没有通用 eval 命令，并在读取错误时脱敏，不显示选项、异常或路径。

别名是本地真实 Ref，最多 128 个，绝不静默替换。用显式 authority 加 ID 消除重复 ID 歧义；重挂前先解除旧别名。Attach 只读取快照、不提交输入。Quit、EOF、detach、断连与 watch 超时都不关闭 Agent；只有成功的 close 才清除别名。新的 CLI 可以发现并挂上同一个存活实例；ID 复用后旧 Ref 仍然是过期 Ref。发现是观察到的局部视图：`complete` 只针对被请求的节点。终端对渲染设上限，命令上限 65536 UTF-8 字节，watch 上限 256 事件/60 秒/每事件 4096 码点，并整行拒绝超限的可执行输入。超限 stdin 结束会话。Stop 不是上游取消/回滚承诺；不会有自动业务重放。

`check-cli-release.py` 为每个复制出的 CLI 进程固定 `BEAMLET_LANG=en`，这样在中文是出厂默认的今天，它的英文文案断言（`error: invalid_command`、健康会话中没有 `error:`）仍然确定；语言切换本身由 `apps/beamlet_cli/test/beamlet/i18n_test.exs` 覆盖。

`check-release.sh` 检查三个重新构建的产物，包括同一 server 副本的三种模式与三个独立前台 CLI stdin 会话。第一个会话在 create 后退出；第二个发现/挂接、操作并通过 EOF 离开；RPC 在第三个显式关闭前证明 authority/PID/incarnation 相同。`check-local.sh` 运行整合门禁并分别记录每个日志。仍需要 Python3.11+ 与既有的六个收尾诊断回归。这些是同主机命名 peer 与确定性夹具，不是物理主机或付费提供者验收。

展示复用已安装的 Owl0.13.1：help/nodes/agents/identity/status 表格、Owl.IO 输出与 Owl.Data 显示边界。表格无论终端宽度都保留 authority/ID 列；发现最多显示 8 条完整身份，并显式给出总数/已显示数/完整性/失败计数。命令与身份处理仍是应用代码。保留窄的原始字节读取器，是因为 Owl.IO.input 会读取无限行、裁剪可执行文本并重试必需的输入/EOF。不需要全屏终端引擎，也不改动依赖/版本。

### 终端语言

终端文案用 Gettext 翻译，出厂提供简体中文（`zh_CN`，默认）与英文（`en`）。CLI 在 `Beamlet.CLI.Runner.run/2` 中、读取任何 stdin 之前一次性确定语言，因此会话不会中途混语言。优先顺序：

1. `config :beamlet_cli, :locale` —— 可信的构建期应用配置，优先级最高（宿主校验器只接受 `enabled`/`allowed_nodes`）；
2. `BEAMLET_LANG` —— 运维环境变量覆盖，接受 `zh`、`zh-cn`、`zh_CN`、`cn`、`en`、`en-us`、`en_US`；
3. `config :beamlet_cli, :default_locale` —— 出厂为 `"zh_CN"`；
4. 共享默认 `zh_CN`。

`BEAMLET_LANG` 故意高于 `:default_locale`，否则出厂默认会让文档里的覆盖方式不可达。任何一步的值不可用都会被跳过，拼写错误只会回退而不会关闭翻译。选择只改变展示：命令语法、表格列与顺序、边界与退出码在两种语言下完全一致，缺失翻译回退到英文 msgid。共享状态/原因词来自 `beamlet_i18n` 目录；CLI 专有文案（help 正文、表头、终端提示）来自 `apps/beamlet_cli/priv/gettext`。

### CLI 复审修复：Unicode 输入与完整身份遍历

Runner 用 `IO.binread/2` 逐字节读取，并在 65536 处停止保留。仅对终端，独占的 stdin 读取器会临时把设备编码设为 Latin-1 以保留原始 UTF-8 字节（否则 Unicode 解码会替换非法字节）；after 块在输出或回调之前恢复原编码，包括失败/EOF 路径。同一终端上的并发读取器不受支持。管道与注入的非终端设备绝不会改变该设置。LF 是分隔符；其前的文本与不完整 EOF 都按原样保留。原生读取错误、非法 UTF-8 与超长行以状态 1 结束；EOF/quit 退出 0。可执行输入绝不会被替换或按截断前缀执行。

`agents [authority]` 替换一份保留的有界发现结果（沿用 1MiB 查询上限）；`agents-page N` 遍历它而不再次查询。每页最多 8 行，按 authority 字符串、ID 字节与 PID 字符串排序。查询的 complete 只指被请求目标；page/count 描述显示完整性。发现仍是最终一致、非原子的集群观察。捕获后 Agent 可能变化或死亡；用 agents 显式刷新，再重新开始遍历。没有隐式重新查询/重试，attach 仍解析当前 ID。

身份单元使用 `id64:` 加无填充的 `Base.url_encode64` UTF-8，attach 可直接接受而不求值。复制整个 token 并提供安全显式别名：`attach host@local id64:dHdvIHdvcmRz a` 会挂接 ID `two words`。简单且非保留的 ASCII ID 仍按字面接受。要寻址以 `id64:` 开头的字面 ID，就对整个 ID 编码。解码后的 ID 仍受共享的合法 UTF-8 1..128 字节约束，包含空白与终端控制字符。token 最多 177 字节；含编码参数的命令仍受 65536 字节限制。没有引入 shell 语法/eval，也没有引入共享的 Agent ID 限制。

已安装的 Owl 使用 Ucwidth 测量 CJK/emoji/组合字符的终端列宽、换行与截断；实际 beam 行为与复制闭包都会被检查。独立的 4096 码点 watch 限制与显示宽度是两件事。

## Durable 存储（显式 profile、数据集 format3）

Durable 存储是 server 共享配置/打包 runtime.exs 中的 opt-in 应用配置；省略 storage 就不会启动数据库。[Storage README](../../apps/beamlet_storage/README_zh.md) 说明初始化、严格的格式/身份拒绝与事务契约；[Agent README](../../apps/beamlet_agent/README_zh.md) 说明按引用 fork、暂停激活与离线轨迹包。归档的 Stage F 证据早于 format2，不是当前验收。

显式 Node 运维初始化只安装全新的 format3 数据集：Agent authority（foundation1 + Actions authority1 + Agent1；迁移 1/100/300）与 Actions journal（foundation1 + Actions journal1；迁移 1/200）。数据集 format3 与不变的 Agent 轨迹 format2 是两回事。旧数据集被拒绝，不转换也不修复。启动/打开绝不迁移、修复、删除或静默转换旧数据集。不要把初始化指向真实已有数据库，不要为了启动成功而删除真实数据库，也不要把旧 authority 文件与新产物混用。保留一致的备份，并部署匹配的完整产物/配置。未知归属的 attempt 在重启后仍被阻塞；绝不要重置它们的身份来重试。forked Agent 以暂停启动，并默认处于未确认的共享环境风险。被 fork/导出引用的内容必须保留；没有自动 GC。

```elixir
config :beamlet_app_server,
  enabled: true,
  node: [roles: [:authority, :executor]],
  storage: [
    adapter: :sqlite,
    database: "/var/lib/beamlet/authority.db",
    dataset_id: "<authority uuid>",
    journal: [database: "/var/lib/beamlet/journal.db", dataset_id: "<journal uuid>"],
    executor_id: "<stable executor uuid>"
  ]
```

作为运维动作一次性安装数据集——绝不在启动时做：

```sh
mix beamlet.storage.migrate --storage /etc/beamlet/storage.exs --roles authority,executor
```

`Beamlet.Node.Storage.status/1` 报告 `admission`（对数据集的实时探测，区别于 Node/Repo 就绪）与各数据集的打开状态。恢复的备份在使用前必须被标记，并在运维者处理前保持拒绝状态、准入关闭。CLI 宿主只做交互，不需要数据库。
