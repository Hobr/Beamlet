# Beamlet

[English](README.md)

**WIP**：首个发布前仍会有破坏性变更。本仓库不保证稳定 API、持久化格式或运维流程；以下说明按当前源码与测试核对，不构成发布承诺。

Beamlet 是用 Elixir/OTP 实现的 AI Agent 系统，运行在同一个可信 BEAM 集群内：用户指定某个节点维持 Agent 的推理循环，循环请求的工作可以安排到其他具备对应能力的节点执行。仓库是一个 Mix umbrella，共十三个应用，把三个关注点分开——**决定做什么（Agent）**、**执行具体工作（Runtime / Actions / Harness）**、**呈现交互（CLI / Web）**；通用执行层与 AI 无关的调用方也可以使用。

## 文档与状态边界

- [目标架构](architecture_zh.md)：首版已确认的架构基线，描述**预期设计**，不是已实现清单。
- [领域术语](GLOSSARY_zh.md)：Agent、Operation、Execution、Result 等领域用语及应当避免的说法。
- [Agent / Operation 持久化设计](docs/architecture/agent-operation-persistence_zh.md)：当前实现所依据的事件优先、按引用恢复的设计。
- [Durable 交付与验收](docs/architecture/persistence-delivery_zh.md)：该设计的验收维度与历史证据位置。
- [部署与复制产物核验](scripts/deployment/README_zh.md)：发布、命名节点、CLI/Web 运维边界及检查脚本。
- [后端开发规范](.trellis/spec/backend/index.md)：应用边界、类型契约、质量命令的事实来源。

已实现且在本仓库测试中覆盖：通用 Actions 契约与 Runtime 执行、原生 Harness 模型/工具、Agent 有界异步编排与事件归约持久化、Node 角色组合、CLI/Server/Web 三个宿主、共享 Gettext 与中英文文案。未验证：物理跨机执行、断电保障、付费模型调用、真实部署与发布产物的现场运维；`scripts/deployment/` 的检查只在本机复制产物上运行，不能当作上述验收。历史研究材料（如 [durable 机制调研](docs/architecture/research/durable-agent-mechanisms.md)）保留原结论，仅作参考。

英文对照目前只有根 `README.md` 的构建命令；完整英文说明属于后续阶段，本文件不会链接尚不存在的英文目标。

## 前置条件

- **工具链**：推荐使用仓库自带的 `flake.nix`（`nix develop`），它提供 OTP 29 与 Elixir 1.20，并把 `MIX_HOME`/`HEX_HOME` 指向仓库内的 `.nix-mix`、`.nix-hex`。不使用 Nix 时需自备 Erlang/OTP 与 Elixir；各应用 manifest 要求 `~> 1.20`（`apps/beamlet_app_web` 仍写着 `~> 1.17`，但请以 umbrella 的 1.20 为准）。
- **网络**：首次需要能访问 Hex 与依赖源（`mix local.hex`、`mix deps.get`）。构建 Web 资源时，esbuild 二进制由 Hex 包从 npm registry 下载、Tailwind 二进制从 GitHub Releases 下载，因此首次资源构建也需要网络。
- **运行时依赖**：默认配置不需要数据库、消息代理或外部服务。开发 Web 只在 `127.0.0.1` 监听（默认端口 4000）；分布式功能需要命名 VM、匹配 cookie 与可达网络，仓库不提供自动发现。
- **可选工具**：部署检查脚本需要 Python 3.11+、EPMD/本地 socket 与原生系统库；`pre-commit` 由 dev shell 提供。

## 应用一览

| 应用 | 已实现的职责 |
| --- | --- |
| [`beamlet_actions`](apps/beamlet_actions/README_zh.md) | 中立 Operation/Execution/Result 契约与有界数据校验，不依赖存储或 Agent |
| [`beamlet_harness`](apps/beamlet_harness/README_zh.md) | 原生模型/工具/环境契约与校验，含 OpenAI 兼容与工作区读取实现 |
| [`beamlet_agent_core`](apps/beamlet_agent_core/README_zh.md) | 纯 Agent 事件归约、上下文构建与继续/分叉决策，不含 OTP 进程 |
| [`beamlet_agent`](apps/beamlet_agent/README_zh.md) | 显式 authority 编排门面：实例生命周期、订阅、委派、持久化输入与暂停恢复 |
| [`beamlet_runtime`](apps/beamlet_runtime/README_zh.md) | Operation 提交/状态/取消/采纳，准入、发现与一次尝试的执行状态 |
| [`beamlet_node`](apps/beamlet_node/README_zh.md) | 供宿主监督的角色组合（interaction/authority/executor）、路由、provider 与观察 |
| [`beamlet_storage`](apps/beamlet_storage/README_zh.md) | 通用 format3 数据集、连接、事务、canonical JSON、artifact 与准入 |
| [`beamlet_actions_storage`](apps/beamlet_actions_storage/README_zh.md) | Operation/attempt/证据/已采纳 Result、执行日志与派发作用域 |
| [`beamlet_agent_storage`](apps/beamlet_agent_storage/README_zh.md) | Agent、事件、检查点、命令去重及只读 Operation 投影 |
| [`beamlet_i18n`](apps/beamlet_i18n/README_zh.md) | 共享 Gettext 后端、语言规范化与公共状态词汇 |
| [`beamlet_app_server`](apps/beamlet_app_server/README_zh.md) | 可选的权威/执行后台宿主及其启动期策略 |
| [`beamlet_cli`](apps/beamlet_cli/README_zh.md) | 可选的前台终端宿主与 IEx 客户端 |
| [`beamlet_app_web`](apps/beamlet_app_web/README_zh.md) | 可选 Phoenix/LiveView 界面宿主：工作台与只读管理页 |

补充专题：[Web 受信宿主](apps/beamlet_app_web/HOST_zh.md)、[Web 工作台与只读管理](apps/beamlet_app_web/WORKBENCH_zh.md)。

## 首次构建

所有命令在仓库根目录执行。

```sh
nix develop            # OTP 29 / Elixir 1.20（或自备等价工具链）
mix local.hex          # 仅首次
mix deps.get           # 依赖固定在同一 mix.lock
mix compile --warnings-as-errors
```

`BEAMLET_BACKEND_BUILD=1` 会把构建切到隔离的 `_build/backend` 并只编译十二个后端应用（不含 Web），用于后端发布；未设置时是完整 umbrella。

## 开发循环

```sh
mix test --seed 631927
mix format --check-formatted
elixir scripts/quality/check-contracts.exs
mix credo
mix dialyzer
git diff --check
```

注意：**从应用子目录执行 Mix 任务不可靠**。`apps/beamlet_app_web` 与 `apps/beamlet_cli` 把 `beamlet_runtime`（CLI 还有 `beamlet_harness`）声明为 `only: :test`，而 `apps/beamlet_node` 没有同样的限制，Mix 会在这些子目录里报 `does not match the :only option calculated`。请始终使用根目录命令（例如 `mix test apps/beamlet_app_web/test`）。

提交钩子可选用：`pre-commit install` 之后，`pre-commit run --all-files` 会依次运行通用文件检查、格式化、测试、Dialyzer、Credo、Sobelow、示例基准与 CycloneDX SBoM。

## 可选的启动路径

普通 umbrella 启动不会启动任何业务宿主：Node、Runtime、Repo 与 stdin 都是显式入口。**每个 VM 只能启用一个宿主**，因为 Node 监督树每 VM 一棵。以下路径都从源码运行，不涉及发布产物。

### Web 界面（Phoenix）

```sh
mix phx.server        # http://localhost:4000
```

dev 配置会启动 esbuild/Tailwind watcher。默认 Web 宿主关闭、目录为空，因此页面可以打开但无法创建实例；需要本地确定性示例时，按 [Web README](apps/beamlet_app_web/README_zh.md) 在 `config/dev.exs` 显式导入 `priv/examples/host.exs`。

### Server 后台（权威/执行）

在启动前的受信配置中启用，然后以 IEx 载入全部应用：

```elixir
# 受信 Mix 配置，例如追加到 config/dev.exs
config :beamlet_app_server,
  enabled: true,
  node: [roles: [:authority, :executor]]
```

```sh
iex -S mix   # 应用按配置启动 Node；不配 storage 时保持内存模式
```

角色、provider、路由与存储选项见 [Server README](apps/beamlet_app_server/README_zh.md) 与 [Node README](apps/beamlet_node/README_zh.md)。

### CLI 前台会话

```elixir
config :beamlet_cli, enabled: true, allowed_nodes: ["authority@host.internal"]
```

```sh
iex -S mix
# 然后在 IEx 中：
Beamlet.CLI.Runner.main()
```

CLI 只做交互，不拥有 authority/executor：需要先有可连的权威节点。命令语法、会话与语言规则见 [CLI README](apps/beamlet_cli/README_zh.md)。

### 作为库嵌入

不需要宿主时，自己监督一棵 Node 树即可（示例取自 [Node README](apps/beamlet_node/README_zh.md)）：

```elixir
{:ok, tree} = Supervisor.start_link([
  {Beamlet.Node, roles: [:interaction, :authority, :executor]}
], strategy: :one_for_one)
```

### 持久化（可选）

不配置 `storage` 就没有数据库。显式持久化需要先用运维动作安装全新的 format3 数据集（启动不会自动建库或迁移）：

```sh
mix beamlet.storage.migrate --storage /absolute/trusted.exs --roles authority,executor
```

数据集、备份与拒绝对象见 [Storage README](apps/beamlet_storage/README_zh.md) 与 [部署说明](scripts/deployment/README_zh.md)。

## 发布与部署检查

```sh
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_server --overwrite
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_cli --overwrite
MIX_ENV=prod mix release beamlet_web --overwrite   # 先构建并 digest 资源
```

三个发布各有独立依赖闭包，都使用 Mix 自带的 `config/runtime.exs`；只有 `RELEASE_NAME` 对应的宿主会被启用。完整步骤、命名节点、检查脚本与已知限制见 [部署说明](scripts/deployment/README_zh.md)。本仓库的检查只覆盖本机复制产物，**不声称**物理部署、真实集群或付费服务已经验收。

## 其他仓库内容

| 路径 | 内容 |
| --- | --- |
| `apps/` | 十三个应用及其 `.formatter.exs`、测试与资源 |
| `config/` | umbrella 共享配置；`runtime.exs` 由发布携带 |
| `docs/architecture/` | 当前维护的持久化设计、交付说明与只读历史研究 |
| `scripts/quality/` | 契约（typespec）覆盖与扫描器回归脚本 |
| `scripts/deployment/` | 发布构建、复制产物检查、CLI/Web 集成夹具 |
| `bench/` | Benchee 示例，仅验证基准工具可用 |
| `.trellis/` | 开发规范、任务与工作记录 |

## 致谢

- [Erlang/OTP](https://www.erlang.org/)
- [Elixir](https://elixir-lang.org/)
- [Phoenix](https://www.phoenixframework.org/)
- [Elixir Desktop](https://github.com/elixir-desktop/desktop)
- [Mob Framework](https://github.com/GenericJam/mob)
- [Nix](https://nixos.org/)
