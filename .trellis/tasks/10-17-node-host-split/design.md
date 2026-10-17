# Node/宿主拆分技术设计

## 1. Scope and evidence

需求唯一来源为同目录 prd.md。当前源码证据见 research/current-seams.md。所有新增模块和命令为计划接口，实施时允许不改变可观察语义的局部命名调整；语义/范围变更必须回到规划。

## 2. Ownership and dependency graph

```text
daemon ──→ node ──→ agent ──→ runtime ──→ actions
cli    ──→ node       └────→ harness
cli    ──→ agent (直接调用时显式声明)
future web ──→ node (本次不开发其业务功能)
```

- Node 继续提供 start_link/child_spec/configuration、Routes/Provider/Runtime 装配和七种角色组合，不再有 Application callback 或独立 release。
- Agent 拥有 Registry、本机列表及 lookup、真实 Ref 和所有业务生命周期。不得反向依赖 Node。
- Node.Cluster 拥有可信名称校验/显式连接与已连接节点筛选。Node.Agents 聚合 Agent 查询；不缓存第二份权威注册表。
- CLI.Client 接收原终端观察逻辑；Session/Command/Renderer 只拥有命令、别名和 UI 生命周期。不复制 Agent 编排或共享发现。
- Daemon.Application 拥有本地配置、默认角色和启动连接策略。不同宿主不共享一份“全局 boot”策略。

## 3. Host startup and test isolation

daemon/CLI Application 默认启动空宿主监督树；宿主配置 enabled: true 才装配 Node。各自 release runtime config 明确启用目标宿主，普通 umbrella 测试不得依赖 MIX_ENV 条件副作用。

- daemon 默认 roles: [:authority, :executor]；可在启动配置选择单一角色。拒绝 interaction/非法组合。
- CLI 固定 roles: [:interaction]，不接受用户配置添加其他角色。
- Node 自身仍支持全部角色组合，未来 Web 直接把 Node 放进自己的监督树即可。
- 保留当前每 VM 一套 Node 的固定注册名设计，不增加同 VM 多 Node 实例框架。宿主独立测试用显式监督与恢复 Application env；真实集成用独立命名 VM。
- 所有 stdin/终端循环在应用成功启动后执行，不能阻塞 Application.start 或 Supervisor.init。CLI 的 standalone runner 负责退出 VM；嵌入测试仅返回退出结果，不调用 System.stop。

## 4. Configuration and cluster bootstrap

发布时一个 daemon 产物包含 authority 和 executor 的代码/依赖；only 选择影响进程树而非编译闭包。CLI 也可能携带 Node 的库级依赖，但不启动 authority/executor。

沿用绝对 BEAMLET_CONFIG 指向可信、operator-owned Elixir 配置。分别新增 daemon_runtime.exs 和 cli_runtime.exs，用 Config.Reader 读取并限制目标宿主设置；不读取旧 :beamlet_node, :boot。配置使用 :beamlet_daemon / :beamlet_cli 命名空间，分别包含 enabled、node options（daemon）、allowed_nodes 和 peers 等已校验字段。

RELEASE_NODE、RELEASE_COOKIE 和分布式端口依然属于 release/VM 参数。保留长名字、服务固定端口、rpc/stop 等 helper 临时端口。配置文件是可信代码；不得使用模型输出指定配置或模块，不记录原始配置、凭据、cookie。

Node.Cluster 复用旧 CLI.authority 的名称格式/255-byte/最多32个可信名字校验；只有明确 allowlist 项可变为节点 atom。connect 不执行自动网段扫描。查询仅使用已连接的可信节点，发现不隐式建立连接。daemon 对配置 peers 逐一做有界的一次连接；连接失败记录安全状态/告警，保留本机服务，不增加后台自动重连循环；CLI 可显式重试 connect。绝不因此重放业务请求。

## 5. Agent list, lookup and cluster discovery

计划接口：
- Beamlet.Agent.list(authority)：返回该 authority 本地安全身份列表。
- Beamlet.Agent.lookup(authority, id)：从本地 Registry 找 PID，向该 Server 请求真实 Ref；不按已知字段自行制造 Ref。
- Beamlet.Node.Agents.discover(nodes)：聚合显式指定且已连接的可信节点，不要求所有节点都是 authority。

Agent.list 的条目只需 authority/id/pid，不读取完整状态或消息历史。使用 Registry 取得有界本机清单；存活性是查询时的观察而非原子快照。lookup 必须核对返回 Ref.authority/id/pid 与目标，保持 incarnation 原样。用 descriptor 附着时检查 expected PID，发现 ID 已复用则 stale_agent；显式 authority+ID 查询表示选择当下实例。已保存 Ref 永远不因查询而更新。

返回契约：
- 本机/远程 list 和 lookup：{:ok, value} 或 {:error, safe_reason}；至少区分 invalid_query / not_authority / not_found / unavailable / timeout / stale_agent。
- discover：{:ok, %{agents: descriptors, failures: node_reason_map, complete: boolean}}；invalid input 整体拒绝。已成功回答为非 authority 的节点不是“空 authority”；结果保留其分类，不把网络失败当空列表。
- complete 仅针对请求的节点集合，不宣称完整/强一致的整个物理集群视图。节点范围超限拒绝，不静默截断；输出达上限明确 partial/limit。

初始边界：最多32节点，每 authority 最多现有128 Agent，聚合并发最多8，总查询接收 deadline 5秒，完整聚合结果最多1MiB（安全理由使用静态 atom）。远程 list 不逐个等候 Agent，lookup 等候必须服从剩余总预算。阻塞/失联查询的 worker 必须在 deadline/调用者退出时回收，禁止产生无界后台请求；deadline 不包含终端同步 IO。必要时缩小上限而非放大业务既有上限。

不返回模型 binding、credentials、options、消息历史或原始异常。保持可信 distribution 的授权模型，不创造多租户权限承诺。

## 6. CLI command and session design

以 release 的前台 start 启动交互循环，不要求 IEx；stdin/stdio 可注入以便脚本测试。最小命令集：

```text
help
connect <trusted-node>
nodes
agents [authority]
create <authority> <absolute-options-file>
attach <authority> <agent-id> [alias]
input <alias> <text...>
status <alias>
watch <alias> [timeout-ms] [event-limit]
stop <alias>
close <alias>
detach <alias>
quit
```

创建选项采用 operator-owned 的绝对可信配置文件，读取显式 agent_options（含 id/model/catalogue/tools），不在终端输入命令中内联 key，不提供通用 eval 命令；沿用现有创建校验而非发明模型协议。文档提供 deterministic 和工具配置示例，明确文件权限和可信代码风险。创建失败只打印安全原因，不 inspect 创建选项或异常。

Session 保存有界的 alias→真实 Ref 映射（上限128）；终端输入采用完整行语法和 UTF-8/字节上限校验，input 不截断可执行内容。命令解析返回结构化动作，由单一 dispatcher 调用共享接口。agents 显示 authority+ID；重名不能模糊 attach。attach 返回当前 snapshot，之后按 watch 订阅，不隐式执行 turn。

watch 迁移原行为：同一 sink subscribe/receive/ack/unsubscribe；事件最多256、接收最多60秒、输出最多4096 codepoints/event；watch 超时不取消业务。第一版同步 watch 有限等待即可，不引入全屏事件驱动 TUI。

detach/quit/EOF 清理观察与本地别名，不 close Agent；断线后的旧 Ref 只产生显式错误，不静默 lookup 替换。用户明确重新 attach 才选择当前实例。close 成功才清除对应别名；失联只报不确定/不可达，不谎称清理完成。多个客户端沿用 Agent 单 active turn/busy 语义，不发明独占附着锁。

## 7. Release and migration

根 releases 改为 beamlet_daemon 和 beamlet_cli 两个入口，各用自己的 runtime config。保留 BEAMLET_BACKEND_BUILD=1 和 _build/backend，backend app 选择加入两宿主但排除 Web；compile 集合与每个 release 的依赖闭包分别检查。

- 同一 daemon copy 分别按三种启动配置测试，不编译三个角色专用 artifact。
- CLI release 不包含 daemon，daemon release 不包含 CLI；均不得包含 Web/Phoenix/Plug/Bandit/WebSock 应用闭包。库级依赖代码存在不等于相应角色已启动。
- 普通 config/runtime.exs 的 Web secret 检查保持，不用假 secret 绕过。
- 旧 backend_runtime.exs、node.example.exs、Node CLI/Application 和 release 引用迁移/删除；scripts/deployment 的检查改为两个宿主，而不是保留旧可执行用于验收。
- Node 中旧 CLI 测试和 release_integration 测试迁入所属 CLI，必要时迁移 distributed test_helper 的排除配置；保留真实 HTTP→Workspace→模型/停止/断线覆盖。
- 不编辑历史 archive/journal 来抹掉旧事实；只更新当前可执行说明/spec/脚本。

## 8. Validation, risk and rollback

风险集中在宿主默认启动冲突、列表/attach 身份竞态、查询超时泄漏 helper、stdin 阻塞、凭据日志与 release helper 端口。检查必须覆盖同名/ID复用、查询中 authority 退出、客户端退出后再次附着以及复制后无源码运行。

采用顺序交付、每个子任务保持普通测试可运行；不依赖破坏性 git reset/clean 回退。出现接口错误先停下一子任务，显式回退该子任务的代码更改或修订设计后重新审核。部署回滚使用保留的上一版本产物和匹配配置，不混用协议版本，不宣称旧 Agent 能跨重启恢复。

没有物理跨机或付费请求验收。所有最终 checks 与实际执行证据由 implement.md 管理。
