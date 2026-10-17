# Agent 实时 Web 工作台

## Goal and Source

交付任务优先的通用 Agent 用户界面，能够发现、打开并多轮使用存活 Agent，看懂当前工作而不需要理解集群。来源：[父任务 PRD](../10-17-beamlet-web/prd.md) R1/R2/R4/R5/R6/R7/R9。

## Requirements

- W1：首页为任务/Agent 入口，preset 可调整且环境条件出现；用户不必先填写底层配置或选择代码项目。
- W2：Agent 列表支持查找和明确身份的重新打开；同名、partial、stale、不可达/未找到分别反馈。
- W3：连续对话以 turn 分界，工具与委派活动可折叠、按需检查；投影与长输出截断/缺失历史明确，所有状态来自真实观察。
- W4：离开不停止，停止不关闭，关闭独立确认；运行中草稿不排队，多观察者冲突与业务确认不明可见。
- W5：桌面/小屏、键盘和阅读滚动可用；安全展示不可信内容，不增加数据库/浏览器记录存储。
- W6：新建、首次输入失败和未知确认按共享 adapter 契约呈现，不通过自动重试或替代创建掩盖错误。

## Acceptance Criteria

- [x] WA1/W1,W6：首页选/调 preset 创建后进入同一 Agent，明确显示实际选项；输入失败保留实例，未知确认不重复 dispatch。
- [x] WA2/W2：CLI 创建实例可发现并打开；同名不同 authority、旧 descriptor replacement、部分空列表和断连按契约显示。
- [x] WA3/W3：真实 deterministic 模型/工具/模型结果及后续 turn 展示；并发工具不伪装成串行，子 Agent 可观察且默认不插入命令。
- [x] WA4/W3,W5：长上下文/输出不失控、截断可见、向上阅读不被强制拉回底部（新活动按钮可回到底部）均已由组件测试与**真实浏览器走查**验证；1440px 与 500x758 内部视口无横向溢出，19 个可见焦点停靠点，键盘 Enter 可激活。未验证：390px 视口（Firefox 本机最小 500px）、触控、读屏、对比度与缩放。
- [x] WA5/W4：离开只移除订阅、Agent 存活；stop 保留实例，close 才结束；运行中不隐式排队，多标签页 busy/unavailable/unknown 真实呈现。
- [x] WA6/W5：凭据/配置不进 DOM/URL/session，CSP/CSRF 与错误页回归保持；刷新只读存活上下文，不出现虚假恢复/归档/历史记录。

## Dependencies and Scope

observation 和 preset/host 两项验收后实施。本任务拥有工作台及可复用 inspector/shell，管理子任务随后复用；不实现 admin 页、durable action、系统提示词、新工具、逐次审批或画布。
