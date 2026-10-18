# C：Agent 事件归约、上下文与暂停恢复：技术边界

## 契约来源

[父技术设计](../10-18-durable-rebuild/design.md)和[目标设计](../../../docs/architecture/agent-operation-persistence.md)共同约束本任务；目标不是已有 API。必须等待 A、B 验收；D 依赖本任务。

## Owning Paths

apps/beamlet_agent/lib/beamlet/agent{.ex,/}、必要 Harness/Node 适配及对应 tests。

## 必须实现

1. 控制状态由版本化纯 reduce(state,event) 得到，不持久 messages/assistant 正文；只在提交后推进内存投影。
2. 固定 through_seq 有界读取，校验连续事件/版本/摘要；checkpoint 为缓存，坏或缺失回退完整历史，坏历史/引用阻塞。
3. 普通对话策略沿合法 input/Operation/accepted refs 构建逻辑请求与来源，来源归新 Operation；指令/策略/工具配置版本明确。
4. 模型步骤与 Tool 批次原子准备后派发，完整回复从 accepted Result 读取；消费只记录引用，按 ordinal 汇合且幂等。
5. inspect 只读；restore 新 generation 且 paused，记录幂等中断并退役旧发送者；continue 只推进合法位置，claimed 未决不重发。
6. 内存模式保留相同编排/上下文行为但不承诺持久恢复；保持订阅展示有界、Agent 控制响应及 helper 生命周期。

## 验证与错误

- 活跃提交投影 == 全历史 reducer == checkpoint+后缀；replay 外部模型/Tool/网络调用为零。
- 原始输入接受后、模型准备前崩溃仍可读；准备/accept/consume 前后恢复无重复执行、重复消费。
- 相同来源与版本得到同一逻辑请求；后续配置/历史变化不修改已准备 Operation；未知证据不能自动进入上下文。
- 缺依赖只阻止执行不阻止只读历史；取消/不确定默认 blocker，旧回调/轮次/代际不推进新状态。
- 事件/恢复/构建边界和超限、长历史分页、helper 真正 DOWN 与既有 Agent/Node 并发回归通过。

具体签名按父 design 中 expected_position、已提交事件/through_seq、prepared 身份、accepted 引用收敛；拒绝非法内容/引用返回安全错误，缺失依赖 blocked，提交结果未知先按 stable ID 读取。不得用 catch 后成功、扩大 timeout/wire cap、降低 lint 或删除场景断言使测试通过。

## 回退与交接

不运行真实数据破坏操作。仅对隔离新格式数据集验证；跨包中间态明确记录，不发布。交付签名、实际验证结果与未完成集成给后续子任务，涉及用户目标变化回父设计审阅；保持单次执行和旧写隔离。
