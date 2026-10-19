# Beamlet Node：显式角色组合

[English](README.md) · [Agent](../beamlet_agent/README_zh.md) · [Runtime](../beamlet_runtime/README_zh.md)

Node 是供宿主监督的库，拥有可信角色组合、公开工具路由、执行器本地 Provider、集群名称解析及有界观察。直接依赖 Actions、Runtime、Harness、Agent、Storage、Actions Storage、Agent Storage 与 Ecto；不依赖 CLI/Server/Web，没有 Application 回调，不自动读取部署配置。

## 启动与本地调用

在仓库根目录用 `nix develop` 获取 OTP 29 / Elixir 1.20，首次执行 `mix deps.get`、`mix compile`。宿主监督树显式安装 `{Beamlet.Node, options}`，每 VM 一棵。roles 是 interaction/authority/executor 的非空去重列表，七种组合均支持。所有角色启动共享 Runtime 与 Routes；authority 加身份岛，executor 先启 Provider 再启带监控的 Runtime，executor-only 不启 Agent Registry。Node 用 one_for_all，基础设施重启不重放业务。

在尚无 Node/Runtime 的根目录 `iex -S mix` 会话：

```elixir
{:ok, tree} = Supervisor.start_link([
  {Beamlet.Node, roles: [:interaction, :authority, :executor]}
], strategy: :one_for_one)
{:ok, facts} = Beamlet.Node.observation()
{:ok, ref} = Beamlet.Agent.start(node(),
  id: "example",
  model: %{provider: "deterministic",
    config: %{"reply" => %{"kind" => "text", "content" => "你好", "calls" => []}}})
:ok = Beamlet.Agent.subscribe(ref)
receive do
  {:beamlet_agent, ^ref, sequence, {:snapshot, initial}} ->
    :ok = Beamlet.Agent.ack(ref, sequence)
    initial
end
```

Directory 异步收报告；用 `Beamlet.Runtime.observation/0` 确认执行报告 fresh/ready 后才做单次 `Beamlet.Agent.input(ref, "hello")`。订阅消费者持续确认各序号并等待当前 turn 的 done/error/paused/stopped，不能把启动注册成功当作模型执行成功。示例使用内建 deterministic，无网络和用户 key。

`Node.configuration(options)` 只预检并返回子项，不启动进程，非法配置返回 invalid_node_configuration；实际 start_link 失败遵循 OTP。所有角色均校验 Runtime limits。profiles 最多 32 个，且仅为 Tool 注册：module/settings/capability 与可选 environment，module 必须在 allowlist 且提供 descriptor/0、invoke/3。WorkspaceRead 在 Provider 启动时校验 root/max_bytes，工作区根留在执行器。旧 type:model profile 拒绝。

model_providers 是最多 32 个 provider ID → 可信已加载模块的固定注册，默认使用 Harness 内建表；不同于 providers 的监控 PID 列表。模型能力是 `model.provider:<id>`，与工具能力并集最多 32；注册就绪不读取 key 环境或调用模型网络。每个 Agent 仍需显式固定 model 绑定。routes 最多 64 个，是可移植工具数据；catalogue 也是纯数据。`Node.profile(id)` 返回 {:ok, route}/:error，`Node.catalogue()` 返回目录，不泄露本地 settings。

## 可信连接与发现

```elixir
allowed = ["authority@host"] # 必须来自可信部署配置
{:ok, authority} = Beamlet.Node.Cluster.authority("authority@host", allowed)
# 显式连接动作（在可达、已配置分布式身份的环境中调用）：
# :ok = Beamlet.Node.Cluster.connect("authority@host", allowed)
{:ok, connected} = Beamlet.Node.Cluster.connected(allowed)
{:ok, identities} = Beamlet.Node.Agents.discover(connected)
```

名称只能是 allowlist 中经验证的 ASCII node@host 字符串，最多 32 个、各 255 字节；仅 authority/2 转换已验证名称。connect 一次尝试，5 秒等待，OTP 握手可能稍后完成。connected 不建立连接或转换 atom。本 VM 必须分布式 alive 且获准才包含在 connected 中。

Agents.discover 接受最多 32 个去重可信 atom，8 并发共享一个 5 秒接收预算（含排队），完整返回最多 1 MiB，为失败项保留 16 KiB。返回 agents/failures/complete；complete 只覆盖请求节点，不是原子集群快照。初始断连拒绝，预检之后 OTP 仍可能重连；远端延迟入口独立开始有限预算，调用者超时不等于远端立即取消。身份只含 authority/id/pid，不含凭证、模型配置或历史。用 `Agent.lookup(descriptor)` 显式连接当前真实 Ref，PID 替换返回 stale_agent。

## 只读观察

`Node.observation/0` 支持本地 nonode@nohost，返回 version/node/configured/roles/services/runtime。无 Node 树是 configured=false、roles=unknown、services=not_configured，即使另有独立 Runtime 也不猜测角色。ready 只表示所需注册存在，不是响应性或 provider 健康探针；读取期间树被替换返回 unavailable。

`Node.observe([node()])` 聚合最多 32 个可信节点，8 并发共享 5 秒，完整信封 1 MiB，显式 failures 与 complete。远端必须入口时已连接，本地无需分布；Runtime 失败时安全 Node 事实可与失败共存。不完整、未报告或陈旧报告不能推出节点死亡、总容量或实际执行位置。

## 显式持久化资源

`Storage.configuration(roles, storage)` 验证宿主 storage 块；`datasets/2` 返回安装参数，不要求 executor 身份。authority 选择 Agent.Storage.Profiles.authority，executor 选择 Actions.Storage.Profiles.journal，均为 format3。SQLite authority/journal 路径必须独立，Postgres authority 配独立 SQLite journal/peer 路径。即使仅一种角色，公共配置仍需通过路径与适配器参数校验。

宿主单独启动 `Storage.start_link(storage: normalized)`，该进程拥有通用 Storage.Host 与默认 Admission。Node roles 配置本身不接受 storage 选项。所有配置资源都参与准入，包括 executor-only journal；缺失、版本不符、恢复备份或不可用资源保留安全原因，准入关闭，不在 boot 建库。

`Storage.runtime/1` 返回 authority/journal 句柄、executor 与新 boot 身份；缺资源返回显式错误，取得句柄不授予准入。`Storage.status/1` 刷新资源与 Admission；已停止 Repo 是 unavailable，不能当作“未配置”。无 storage/仅 interaction 的宿主不需启动 Repo。

运维者显式调用 `Storage.Operator.initialize(roles, storage)` 或从根目录运行：

```sh
mix beamlet.storage.migrate --storage /absolute/trusted.exs --roles authority,executor
```

该文件是会求值的可信 Elixir keyword 配置，包含部署路径/连接参数，不提交仓库。初始化依次进行，不是跨数据集原子事务；已有数据集拒绝，失败不重试新建。命令只停止自己启动的 Repo。旧 authority2/journal1 拒绝，使用新路径保留旧数据，不自动升级或覆盖。轨迹包 format2 与数据集 format3 独立。

## 验证入口

所有命令从仓库根目录执行：

```sh
mix test apps/beamlet_node/test --seed 631927
mix compile --warnings-as-errors
elixir scripts/quality/check-contracts.exs
```

命名节点分布式测试另行运行，不将普通本地或同宿主 peer 结果称为物理跨机验收。取消、清理与不确定性以 [Runtime](../beamlet_runtime/README_zh.md) 和 [Agent](../beamlet_agent/README_zh.md) 契约为准。
