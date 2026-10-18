# D：引用式 fork、历史导出与产品验收：技术边界

## 契约来源

[父技术设计](../10-18-durable-rebuild/design.md)和[目标设计](../../../docs/architecture/agent-operation-persistence.md)共同约束本任务；目标不是已有 API。必须等待 A、B、C 的契约与局部验收通过；最后交付父任务 AC1–AC7。

## Owning Paths

Agent history/trace_export、Storage history/fork、apps/beamlet_app_server、beamlet_cli、beamlet_app_web、scripts/deployment 及 specs。

## 必须实现

1. 同权威 fork 直接继承不可变引用清单，来源事实保留，无父事件链递归/新执行实体或正文 transcript。
2. 新 Agent paused/await_input，不继承 pending/命令去重/消费/provider session；共享环境未确认停止默认禁执行，显式风险接受留痕。
3. 历史与导出固定高水位，遍历输入/Operation/Result/artifact 闭包，区分 performed/inherited、缺失/脱敏；只读不需要 provider 在线。
4. 产品接线使用新格式/契约，Server/CLI/Web 既有功能继续可用；提供因果与上下文来源可查询数据，不新增图 UI。
5. 更新源码 spec/README/部署操作为实际实现；新格式显式初始化，真实数据库不删除，旧数据只拒绝不偷偷转换。

## 验证与错误

- 父 Agent 不运行时新 Agent 可按直接内容引用恢复；旧结果不推进新 Agent、继承 usage 不算新费用。
- 并发导出不漂移，所有引用摘要可验证；缺内容明确阻塞，不把哈希当正文。
- 两独立 OS 进程 durable-e2e、named peer 故障窗口与调用计数、本地/分布式×内存/durable 覆盖。
- 全伞、严格静态、catalogue drift、backend build、受影响 copied/named release 和真实双库通过并记录；缺前提不记通过。

具体签名按父 design 中 expected_position、已提交事件/through_seq、prepared 身份、accepted 引用收敛；拒绝非法内容/引用返回安全错误，缺失依赖 blocked，提交结果未知先按 stable ID 读取。不得用 catch 后成功、扩大 timeout/wire cap、降低 lint 或删除场景断言使测试通过。

## 回退与交接

不运行真实数据破坏操作。仅对隔离新格式数据集验证；跨包中间态明确记录，不发布。交付签名、实际验证结果与未完成集成给后续子任务，涉及用户目标变化回父设计审阅；保持单次执行和旧写隔离。
