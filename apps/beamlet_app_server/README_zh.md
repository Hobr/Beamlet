# Beamlet Server

> 语言状态：本页是当前维护的中文版本。本应用尚无英文 README，英文对照属于后续语言阶段；此处不链接尚不存在的文件。

后台 OTP 宿主，直接依赖 Node 与通用 Storage；通过 Node 组合 authority/executor 与可选存储，不依赖 CLI、Phoenix 或 I18n。默认禁用，普通加载只启动空树。启用后默认 authority+executor，也接受其中任一角色，不接受 interaction；每 VM 仅一棵 Node 树。

## 配置与启动

先在启动前的受信 Mix 配置中声明：

```elixir
import Config
config :beamlet_app_server,
  enabled: true,
  node: [roles: [:authority, :executor]],
  allowed_nodes: [],
  peers: []
```

从仓库根目录运行 `iex -S mix`。仅启动角色不代表提供方、资源与工作区已配置可用；实际模型注册、executor profiles、环境及资源限制归 Node。可先无副作用验证策略：

```elixir
{:ok, policy} = Beamlet.Server.configuration(node: [roles: [:authority]])
false = policy[:enabled]
nil = policy[:storage]
# 启用宿主后可读取；未启用时返回 configured: false 的公开事实
{:ok, facts} = Beamlet.Node.observation()
```

严格宿主键为 enabled/node/allowed_nodes/peers/storage，重复或未知键返回 invalid_server_configuration。peers 最多 32 个不同受信名称且须在 allowlist 中；临时 bootstrap 在 Node 启动后顺序连接一次，每次连接调用预算 5 秒，失败只按序号记录并保留本地服务。无重连或业务重放；OTP 已开始的握手可能稍后完成。

## 持久化与生命周期

不配 storage 时保持临时模式且不开数据库。显式配置后，authority 打开 authority 数据集，executor 打开 journal；格式 3 安装/迁移由运维入口预先执行，启动不会替缺失数据集自动初始化。配置存在不等同 durable admission，需打开后的实时探测准入。`Beamlet.Node.Storage.status/0` 与 `runtime/0` 提供当前状态/适用数据集结果；角色注册就绪与存储准入是两个事实。存储接口及真实描述符示例见 [Node](../beamlet_node/README_zh.md)。

## 发布

根目录执行 `BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_server`（不写名称时也是默认 release）。产物位于 `_build/backend/prod/rel/beamlet_server`，使用 `bin/beamlet_server start` 前台运行，或原生 daemon/rpc/pid/stop。发布自带 runtime.exs 按 RELEASE_NAME 只启用本宿主，采用原生 RELEASE_NODE/RELEASE_COOKIE，不需 Web SECRET_KEY_BASE。发布闭包不含 CLI/Web/I18n；不要把整个 umbrella 启动等同独立发布闭包。命名节点、控制端口及复制产物检查见 [部署说明](../../scripts/deployment/README.md)。

## 开发与核验

以下命令均在仓库根目录执行。项目开发环境由 `flake.nix` 提供 Elixir 1.20 / OTP 29；先进入 `nix develop`，已有工具链也须满足根及各应用 Mix 要求。依赖尚未安装时先运行 `mix deps.get`。

```sh
mix compile --warnings-as-errors
mix test apps/beamlet_app_server/test
mix format --check-formatted
git diff --check
```

完整质量检查由集成阶段执行；示例启动、发布及远程调用需要对应运行环境，不属于仅检查文档即可证明的部署验收。
