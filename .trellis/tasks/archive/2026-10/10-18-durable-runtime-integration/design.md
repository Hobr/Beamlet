# B：Runtime 持久操作与并发结果采纳：技术边界

## 契约来源

[父技术设计](../10-18-durable-rebuild/design.md)和[目标设计](../../../../../docs/architecture/agent-operation-persistence.md)共同约束本任务；目标不是已有 API。必须等待 A 的新格式与事务契约验收；C 依赖本任务。

## Owning Paths

apps/beamlet_runtime/lib/beamlet/runtime*.ex 与子目录、apps/beamlet_runtime/test、必要 Actions/Storage 适配。

## 必须实现

1. 移除 expected Agent accept_seq 协议；独立 Operation CAS 采纳结果，Agent 只经明确事件消费；模型/Tool 都支持 agent/turn/step 归属。
2. 接收 A 的已准备 Operation/attempt，submit 不重复创建或改变确定请求；description 摘要固定来源和有效非敏感参数，临时凭据不持久。
3. 保持 prepared/send_claimed、start_intent、terminal receipt、accepted-before-notify；本地与远端同一路径，双库非原子窗口显式。
4. 迟到证据可保留，accepted Result 不覆盖；旧控制代不能发起新工作，证据查询/重传不能启动 Worker。
5. 持久存储/日志失败阻止相关准入，不降级；保留 deadline/cancel 首触发 provenance 与真实终止分类。

## 验证与错误

- 两个 sibling Operation 反序/并发完成均可独立采纳，无 Agent 版本争抢或事件预留空洞。
- 相同 admit/receipt 幂等不重复 Worker，claim 后断连和重启不重发；unknown/not_found 不被解读为未执行。
- 权威 accepted 内容 executor 离线仍能读；采纳写失败无正常 sink completion。
- 本地与 named peer 覆盖凭据不落库、完整 envelope 限制、取消/超时/成功竞争和准入故障。

具体签名按父 design 中 expected_position、已提交事件/through_seq、prepared 身份、accepted 引用收敛；拒绝非法内容/引用返回安全错误，缺失依赖 blocked，提交结果未知先按 stable ID 读取。不得用 catch 后成功、扩大 timeout/wire cap、降低 lint 或删除场景断言使测试通过。

## 回退与交接

不运行真实数据破坏操作。仅对隔离新格式数据集验证；跨包中间态明确记录，不发布。交付签名、实际验证结果与未完成集成给后续子任务，涉及用户目标变化回父设计审阅；保持单次执行和旧写隔离。
