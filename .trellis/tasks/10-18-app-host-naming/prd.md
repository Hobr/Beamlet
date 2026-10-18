# Server/Web 宿主应用命名与原生 Release 入口

## Goal

用 `beamlet_app_*` 标识独立宿主入口，清楚区分可嵌入能力与部署组合；通过 Mix Release 原生机制完成打包、运行和运维。

## Background

- 用户确认使用 `beamlet_app_server` / `beamlet_app_web` 应用名、`Beamlet.Server` / `Beamlet.Web` 模块及 `beamlet_server` / `beamlet_web` Release 名称。
- 用户确认一次性移除旧身份及入口，不保留兼容层。
- 基线 `13824da` 包含 `6041b20`：所有 Release 已使用 Mix 默认 `config/runtime.exs`，已有独立 Web Release，旧外部配置入口已删除。
- `beamlet_node` 是无 Application 回调的可嵌入库；Server 组合 Node、可选存储及初始 peer 连接，Web 自行组合交互 Host。
- 代码证据与影响位置见 `research/current-state.md`。

## Requirements

### R1 — 宿主命名

- `apps/beamlet_daemon` / `:beamlet_daemon` 改为 `apps/beamlet_app_server` / `:beamlet_app_server`；`Beamlet.Daemon` 及子模块改为 `Beamlet.Server`。
- `apps/beamlet_web` / `:beamlet_web` 改为 `apps/beamlet_app_web` / `:beamlet_app_web`，模块仍为 `Beamlet.Web`。
- `app` 表示架构上的独立宿主定位；其他 `beamlet_*` 仍可为 OTP applications。

### R2 — Release 与原生运维

- Server / Web Release 分别为 `beamlet_server` / `beamlet_web`；默认 Release 为 `beamlet_server`，未指定名称的 `mix release` 选择它。
- 使用原生 `start`、Unix `daemon`、`remote`、`rpc`、`pid`、`stop` 等能力；systemd/容器部署推荐前台 `start`。
- 沿用默认 `config/runtime.exs` 和 `RELEASE_*`，不恢复 `BEAMLET_CONFIG`、自定义 runtime_config_path 或进程管理包装。

### R3 — 配套迁移与行为约束

- 同步更新配置、应用身份引用、依赖、Phoenix 静态资源和 Gettext 归属、资源路径、测试、发布检查、部署样例及当前规范。
- Node 保持可嵌入、显式监督；每 VM 最多一棵 Node 树。
- 保持宿主默认角色、可选存储、peer bootstrap、Web/CLI 用户行为及各 Release 的依赖隔离。
- Web UI、会话 cookie 和 salts 不因应用改名而改变；CLI 应用及 Release 名称不变。

### R4 — 一次性迁移

- 删除旧应用身份 `:beamlet_daemon` / `:beamlet_web`、旧 `Beamlet.Daemon` 模块及旧 `beamlet_daemon` Release 入口。
- 不提供模块转发、旧配置回退、双应用注册、Release 别名或旧目录入口。
- 提供旧→新迁移说明；部署使用重建的完整 artifacts 和对应新配置。
- `beamlet_web` 作为继续使用的 Release 名称不属于待删除身份；原生 `daemon` 术语仍有效。

## Acceptance Criteria

- AC1 (R1): umbrella 识别两个新应用及正确 Application 回调；Server 使用新命名空间，Web 保持原命名空间。
- AC2 (R2): 默认与显式 Server 构建产出 `beamlet_server`；Web Release 仍为 `beamlet_web`，分别启动对应新应用。
- AC3 (R2, R3): Server/Web/CLI 的复制 artifacts 通过依赖闭包及原生命名 start/RPC/pid/stop 检查；Unix Server 后台模式可启动并清理退出。Server 无需 Web secret，Web 缺失 secret 仍拒绝启动。
- AC4 (R3): 普通加载不自动启动 Node；Server 三种角色模式、Web Host 与命名 peer 测试保留原有断言，存储启动和 admission 行为不变。
- AC5 (R3): Web HTTP、摘要 CSS/JS、Gettext 目录归属及现有页面测试通过，用户界面和会话配置保持原行为。
- AC6 (R3): 当前部署文档、样例及检查脚本使用正确新命名；当前规范可定位真实代码；保留原生 daemon 用语与历史证据。
- AC7 (R1–R4): format、warning-fatal compile、普通及实际命名分布式测试、Credo、Sobelow、Gettext、Dialyzer 和适用发布/存储 gate 有当前任务证据；明确记录未执行及失败项。
- AC8 (R4): 新应用清单/产物无旧应用身份与旧模块；旧 Server Release 构建名不再可用；无兼容入口，迁移说明明确新配置和命令。

## Out of Scope

- 合并 Server 与 Node、改动 Agent/Runtime/Storage 协议或角色模型。
- 新增 Server+Web 同 VM 部署模式、CLI 改名、通用宿主框架或外部配置系统。
- 付费模型调用及物理跨主机部署验收。
- 重写归档任务/日志、更新历史 SBoM 快照、无关依赖升级或 UI 改动。

## Planning State

兼容性与范围决策已收敛，完整规划已获用户批准，任务已进入 `in_progress`。设计及执行检查表分别见 `design.md`、`implement.md`，上下文清单为 `implement.jsonl` / `check.jsonl`。实现与验证已完成，独立检查结论为 READY，当前待提交确认；证据见 `research/implementation-evidence.md` 和 `research/independent-review.md`；本任务作为一个需要协同改动配置及发布闭包的集成迁移管理。
