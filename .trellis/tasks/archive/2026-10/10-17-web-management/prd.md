# Web 只读管理页面

## Goal and Source

让同一可信空间的使用者查看支撑 Agent 的节点/能力与配置，并从工作台定位当前问题；不是集群运维平台或管理员权限系统。来源：[父任务 PRD](../10-17-beamlet-web/prd.md) R8，以及 R1/R3/R9/R10。

## Requirements

- M1：节点视图独立呈现连通、配置角色、服务就绪、报告年龄/新鲜度、能力、环境和可用容量；未知/partial 不伪装为空或健康。
- M2：preset/能力页展示可信启动配置的安全摘要、默认选项和不可用原因；不是任意配置或密钥编辑器。
- M3：当前诊断从工作台错误/活动关联已有 Agent/turn/operation 身份并复用检查组件；无数据的执行位置/轨迹不猜测。
- M4：管理为只读视图，不提供任意 RPC、终端、重启、角色热切换、在线写配置或恢复控制；导航分区不宣传为授权隔离。
- M5：不增加指标/日志数据库、持久诊断、原始异常/进程状态 dump 或秘密暴露；开发 debugger/dashboard 门控保持。

## Acceptance Criteria

- [x] MA1/M1：authority-only、executor-only、组合角色和节点不可达/服务未就绪/无报告/过期有不同可见结果；报告仅有 available 时不显示伪造总量。
- [x] MA2/M2：preset 页面与创建表单的同一 safe descriptors 一致，未知能力及缺失环境明确，无法在线修改。
- [x] MA3/M3：用户工作台错误可打开共享诊断；失效身份和未知关联能安全退化，不读取私有运行状态或补造时间线。
- [x] MA4/M4,M5：事件/路由无管理 mutation，页面/log/session 无测试秘密或根配置；CSP、CSRF 和 dev-only 暴露回归通过。
- [x] MA5/M1,M5：刷新有时间/并发/容量上限，失败保留明确的最后观察/未知状态；无存储或指标 exporter 被引入。

## Dependencies and Scope

共享 observation 与 preset/host 必须完成；顺序安排在 workbench 后以复用 shell/inspector。此任务不反向修改父产品范围；无多用户/登录、配置写入、Web release 或完整 tracing。
