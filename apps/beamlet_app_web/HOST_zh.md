# 受信 Web 宿主与适配 API

[应用入口](README_zh.md) · [工作台与管理](WORKBENCH_zh.md) · [现有英文专题](HOST.md)

Endpoint 与后端 Host 分开启动：默认页面可访问，但 Host 空树、无目录、无角色或提供方调用。`config :beamlet_app_web, :host, settings` 只在启动时生效。确定性本地演示见 [host.exs](priv/examples/host.exs)，须审阅后从 `config/dev.exs` 显式导入；不会自动配置付费模型、凭据或工具。

## 启动策略

settings 是无重复键的 keyword：enabled 默认 false，node 默认 `[roles: [:interaction]]`，allowed_nodes/peers 默认空列表，catalogue 默认空映射。未知、重复键或非法目录返回 invalid_web_host_configuration。Node 校验具体选项，角色必须含 interaction，支持其四种组合。每 VM 只运行一棵 Node，CLI/Server 宿主保持关闭。

enabled Host 按 rest_for_one 顺序拥有 Node、Presets、Handles 与临时 Bootstrap。导航进程丢失不会重启前面的 Node；Node 丢失会重启后续进程并清空导航。嵌入 authority 丢失可能失去自己的活 Agent；远端存活实例可重新发现。配置/环境修改不会在线变更宿主。

peers 最多 32 个不同受信节点名，须属于完整验证的 allowed_nodes。Bootstrap 启动确认后顺序连接一次，每次 Cluster 调用预算五秒；失败保持本地服务，无后台重试。宿主消失/截止清理调用者，OTP 已开始的握手仍可能稍后完成。浏览器操作不连接节点。

## 目录模式与公开草稿

catalogue 是严格 atom 键映射，包含 models/tools/environments/presets/authorities 五种以公开字符串 ID 为键的映射及 default_authority（公开 ID 或 nil）。各类最多 32 项，tools 最多 64 项。ID/title 为非空有效 UTF-8，最多 128 字节；description 可选，最多 2048 字节。每项均有 title，其他字段如下：

| 条目 | 字段与边界 |
| --- | --- |
| model | binding：显式不可变 Agent 模型绑定，提供方必须在受信 Node model_providers 注册表中 |
| tool | route：不含 environment 的可移植 Tool 路由；descriptor：匹配的中性描述符；environments：允许的公开环境 ID，空表示不要求环境 |
| environment | value：不透明核心环境值，不能将工作区根目录或提供方 settings 暴露为选项 |
| preset | model、tools 默认公开引用，可选 environment 默认引用 |
| authority | target 为 :local 或允许列表中的受信节点名 |

Tool 描述符名称全局唯一，路由/目录与核心限制在启动时校验，不探测提供方、执行工具或从环境变量寻找凭据。执行根目录/settings 归 Node profiles。未配置 default_authority 时草稿保留 nil，需显式选择，不做可用性回退。

`Presets.describe/0` 只返回标签、描述、预设引用、工具允许环境与默认 authority，不返回绑定、凭据、路由、真实环境值或目标节点名。`Presets.reset(id)` 返回全新 `{:ok, draft}`，不修改目录/实例。draft 的字符串键严格为 preset/model/tools/environment/authority/title/task：工具 ID 不同且最多 64 个，task 为最多 65536 字节有效 UTF-8，可为空；表单自身要求任务文字。只有选中工具要求环境时才必选，且须兼容所有相关工具。非法草稿返回 invalid_draft。

```elixir
# 前提：已显式启用 priv/examples/host.exs 的 basic 预设
public = Beamlet.Web.Presets.describe()
{:ok, draft} = Beamlet.Web.Presets.reset("basic")
{:ok, resolution} = Beamlet.Web.Presets.resolve(Map.put(draft, "task", "你好"))
```

resolution 含 authority/task/options，包括匹配 tools/catalogue、不可变 model binding 与最多 4096 序列化字节的 display_metadata。它只可留在服务端 worker，不进入浏览器 assigns、session、URL 或日志。可信标签说明配置来源，并不证明授权或清除模型回显中的秘密。纯函数 configuration/2,3、describe/1、reset/2、resolve/2 供启动/测试使用；运行进程没有在线修改目录接口。

## 创建、输入与不确定结果

`Agents.create(draft)` 一次 start，确认后一次 input，结果分开处理：

| 返回 | 含义与后续 |
| --- | --- |
| `{:rejected, :invalid_draft}` | 未派发创建 |
| `{:create_unknown, %{authority: atom, id: id}}` | 未确认 Ref；即使静态远端错误也不证明未创建，保留身份供显式发现 |
| `{:created, %{ref: ref, navigation: navigation, input: outcome}}` | 已确认实例，导航与输入失败均不丢弃 Ref |

navigation 为 `{:ok, handle}` 或静态错误。`Agents.input(ref, text)` 返回 `{:accepted, turn}`、已知 `{:rejected, reason}` 或 `:input_unknown`。没有自动重发、重建或确认丢失后关闭实例的路径。

远端创建使用五秒 erpc，输入使用现有 Agent 五秒控制预算；本地 DynamicSupervisor admission 没有整调用有限超时。Presets 缺失可能在派发前令调用者退出。LiveView 必须使用 OwnedCall 的有限 UI 调用者、pending 锁、退出处理与不确定身份保留。调用者死亡既不回滚业务，也不撤回排队的本地创建，迟到创建可能留下空闲 Agent。它不是持久 exactly-once 保证。

导航缺失或调用超时返回 unavailable；已确认 Ref 保留，单次 input 仍可派发。超时的映射插入可能稍后完成，但只保存有界身份数据。

## 临时导航与部署边界

`Agents.discover(trusted_atom_targets)` 保留 Node complete/failures；信任目标仅由 Cluster 从受信配置解析。非分布式本地发现须显式含 `node()`。`Agents.attach(exact_descriptor)` / `Handles.remember/1` 经精确查找后返回 24 随机字节编码的 32 字符 Base64url 句柄。

`Handles.fetch/1` 重核描述符与完整 Ref/incarnation；同名新实例不重绑定。无效/过期/替换返回 stale_handle，进程不可用返回 unavailable，满额返回 handle_limit。最多 4096 条，一小时空闲过期，每 60 秒清理；只保存 descriptor/Ref/触达时间，重启清空，不保存转录或凭据，不拥有/关闭 Agent。句柄不是权限令牌。

开发保持 loopback。共享部署须受信网络或运维管理的认证反向代理，以及所需核心命令/查询/订阅/环境权限；外部登录本身不提供逐用户核心授权。未提供账号/RBAC/租户隔离或公共匿名部署。保留 CSP、CSRF、origin、转义及生产 SECRET_KEY_BASE 校验。无浏览器转录存储、文件转录、数据库界面、在线恢复/重放/系统提示编辑器；管理只读。

语言不是 host 键。`config :beamlet_app_web, :default_locale` 只设呈现默认；查询与会话规则见 [工作台语言](WORKBENCH_zh.md#语言与会话)。根目录核验命令见 [README](README_zh.md#开发与核验)。
