# Workbench Execution Plan

## Preconditions

- [x] 父子最终规划已获用户“批准”（2026-10-17）；observation 与 presets/host 完成工程验收，见各任务 research/acceptance.md。
- [x] 公共 display/metadata、safe option descriptors、create/input outcome 与 handle 契约实际存在，见 live-observation.md 与 web-host.md；不用私有状态补洞。

## Ordered work

- [x] 更新首页/布局和 verified LiveView routes；保留安全回归。
- [x] 完成任务优先 preset 表单、调整/reset、风险摘要、必要环境与高级选项。
- [x] 发现/搜索/打开 exact descriptor，展示 partial 和 stale，不将 partial empty 当作零实例。
- [x] 接入 opt-in snapshots、sink ack、task/monitor cleanup 与 generation/ref 匹配。
- [x] 实现 turn/工具/子 Agent 卡片与 inspector，截断/unknown/missing-history 明确。
- [x] 实现 stop/close/leave 和 busy/uncertain UI；不增加后台业务重试。
- [x] 增加 LiveView 集成测试：确定性多轮、CLI 协作、订阅退出、超时、XSS/nonce、大小/慢 sink。
- [x] 浏览器走查 desktop/mobile、键盘、长输出、滚动、断连：已用 geckodriver+Firefox 实际执行（34 通过/1 受阻/0 失败，无产品缺陷）。受阻：390px 视口被 Firefox 钳制到 500px、浏览器 console 日志 API 返回 405、浏览器内 busy/多观察者未复现；断网重连、触控与读屏未验证。
- [x] 提供稳定共享组件给 management，更新已实现 Web spec。

## Validation and rollback

计划：mix test apps/beamlet_web/test；mix format --check-formatted；mix compile --warnings-as-errors；mix credo --strict；mix sobelow；资产用 umbrella 根级 mix tailwind/esbuild beamlet_web（child 目录命令受 umbrella :only 不一致限制）。本地和真实 named 远程整体验收见父 implement.md，不以 mocked event 代替核心真实工具链。

回滚路由/页面或停用业务入口，不因 navigate/unmount 关闭 Agent。若 SDK/display 不足，返回前置子任务修契约，不在 UI 用 :sys.get_state 或无限积累事件。
