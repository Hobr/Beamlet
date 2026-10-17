# Agent 与节点安全观测契约

## Goal and Source

为用户工作台与只读管理页提供真实、有界、无凭据的公共观察能力，不把 Web 耦合到私有进程状态。来源：[父任务 PRD](../10-17-beamlet-web/prd.md) R6/R8/R9/R10；现有快照缺少显示上下文，节点无统一产品观测入口。

## Requirements

- O1：展示 Agent 已保留的内存上下文和当前工具/委派活动，身份及截断/覆盖范围明确；不伪造 token 流、轨迹或内部思考，不另存事件日志。
- O2：为新建实例保留可选的安全显示名称、preset 和有效公共配置标识，不暴露模型 binding/凭据/工具根配置；旧调用无需填写。
- O3：提供节点角色/服务就绪事实及报告能力、环境、可用容量与新鲜度；缺失和部分失败可见，不将报告缺失解释为死亡。
- O4：所有读取和投影有时间/数量/字节上限，订阅沿用 credit 与 coalescing；不改变 Agent 模型上下文、操作准入或生命周期。
- O5：保持默认 Agent snapshot/subscription、存活发现身份隔离和既有 CLI 行为，核心库不依赖 Phoenix/Web。

## Acceptance Criteria

- [x] OA1/O1,O2：确定性多轮模型/工具任务能获得安全上下文与活动，实例有效配置来源可见；旧选项无 metadata 也可正常使用。
- [x] OA2/O1,O4：长文本、复杂工具返回和并发活动触发明确截断，未修改模型请求上下文；超过 UI budget 不使原本有效的默认 snapshot 失败。
- [x] OA3/O3：authority-only、executor-only、组合角色及无报告/过期/读取超时有不同结果；容量只展示有证据的量，报告 age 在源 VM 正确计算。
- [x] OA4/O4,O5：慢 sink、ack、sink DOWN、失效 Ref 和远程读取停顿有界；读取零模型/工具 dispatch，默认 CLI/订阅和 identity-island 回归保持。
- [x] OA5/O2,O5：测试凭据/原始模型配置/根设置不在观测及安全错误中；默认返回形状兼容，公共接口无需 Web 依赖。

## Dependencies and Scope

这是首个交付。共享契约验收后，preset/host 才基于 metadata 创建，workbench/management 才消费。无数据库、历史存储、恢复、调度策略变更或全面分布式 tracing。技术细节见 design.md。
