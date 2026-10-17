# Management Execution Plan

## Preconditions

- [x] 父子规划已获用户“批准”；observation、presets/host 已工程验收，workbench source 独立检查通过且 shell/inspector 可复用。用户明确暂不使用浏览器验证；可继续本子任务非浏览器工作，浏览器验收保持延期。
- [x] 读取 parent design §6、当前能力 research 和本任务 spec manifests。

## Ordered work

- [x] 加入只读导航/路由与共享布局，不把导航当权限边界。
- [x] 节点页面使用 public observation，区分 connection/readiness/report age/unknown/partial；只显示真实 available。
- [x] preset 页面使用同一 browser-safe catalog projection，显示真实引用/默认值与启动来源。
- [x] diagnostics 复用 Agent 活动组件与身份链接；失效/未知不回退私有状态读取。
- [x] 增加 bounded page refresh、task ownership/unmount cleanup，无连接/业务 probe 副作用。
- [x] LiveView/ConnCase tests 覆盖未就绪/无报告/过期/partial、伪造 handle/ID、秘密不泄露和零 mutation。
- [x] 完成与工作台的桌面/小屏导航与错误跳转走查，更新已实现 spec；交付父任务最终 AC 复核。

## Validation and rollback

计划：mix test apps/beamlet_web/test；mix format --check-formatted；mix compile --warnings-as-errors；mix credo --strict；mix sobelow；资产用 umbrella 根级 mix tailwind/esbuild beamlet_web（child 目录命令受 umbrella :only 不一致限制）。父 implement.md 还要求完整集成、named peers、全量测试/静态检查与实际浏览器证据。

回滚去除 admin 导航/路由；不改变 Node 角色或运行实例。当前证据不足的字段宁可显示 unknown，也不得通过 raw state/config dump 实现看似完整的控制台。
