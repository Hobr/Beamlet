# Workbench Design

## Authority and layout

遵循[父设计 §3/§5](../10-17-beamlet-web/design.md)。Phoenix LiveView 页面复用现有 CoreComponents/Gettext/verified routes；不另建 SPA。

/ 为列表+任务入口，/agents/new 为展开配置，/agents/:handle 为工作区。左栏 Agent 列表，中栏 turn-aware 对话，右侧 inspector 按需打开，小屏收成 drawer。活动/错误组件供管理页复用。替换脚手架首页文字断言，但保留 nonce/CSP/错误页测试。

## Boundary/state

Browser 只发送有界 ID 和文本；Host/Presets/Agents adapter 解析，Handle 映射服务端身份，公共库做实际业务与读取。default snapshot 不能当作完整显示接口，消费前置子任务的 opt-in display。snapshot 为替换投影，不是可无限 append 的事件流；保留源 entry/activity IDs 与 turn/ref identity。

分开 business state、command pending、observation connection。读/命令在有 owner 和有限预算的任务中执行，订阅 sink 自己 ack；切换卸载取消观察任务，不取消 Agent。每次 mounted selected Agent 可有一个订阅，不对整个列表无界订阅/轮询。忽略来自旧 ref/command generation 的迟到响应。

输入时允许本地草稿，active turn 不排队；服务端 busy 是最终事实。已知创建/输入结果和不确定确认用不同提示。close 在更多菜单确认，stop 不等价于远程回滚。子 Agent inspector 默认观察，不自动授予介入父委派任务的行为。

## Rendering/security

用户/模型/工具文本默认 escaped；首版不需要引入富 Markdown/任意 HTML 渲染器。长输出受共享限额约束。scroll hook 只管理 DOM 滚动，不把内容保存到 localStorage；用户不在底部时用新活动提示。keep CSP nonce，禁止为脚本 hook 开放 unsafe-inline/eval。未知实例配置不能通过读取 model binding 来复制；重新选择 preset。

## Non-durable lifecycle and rollback

Web handle 丢失重新发现，Agent 上下文缺口显示缺失；既有内存上下文不被包装成持久历史。Web host 同时承载 authority 时重启可能结束 Agent，须如实提示。回滚隐藏工作台路由/入口即可，不关闭存活业务实例。
