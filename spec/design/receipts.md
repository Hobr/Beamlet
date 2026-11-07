# Operation / Attempt / Report 回执契约

本契约区分三段应用层确认. Transport 发送返回, 订阅匹配, 启动公告及心跳均不代替回执. 当前全部保留仍是进程内存, 不承诺持久化, 跨重启恢复或外部效果 exactly-once.

## 三段确认

| 回执 | 方向 | 允许确认的事实 | 不允许推断 | 本批状态 |
| --- | --- | --- | --- | --- |
| Operation 接纳 | Authority -> Client | 指定 Authority 已校验并保留不可变 Operation 及其原接纳结果 | Worker 已接纳, 开始执行, 最终成功 | 仅定义契约, 未实现独立回执 |
| Attempt 接纳 | Worker -> Authority | 指定 Worker 已校验并接纳该 Authority 的原 Attempt | 执行已开始或完成, 没有外部效果, 已产生 Report | 已实现, 含原授权有界重投 |
| Report 收录 | Authority -> Worker | 指定 Authority 已校验并保留完整 Report | 已采用为 Operation 最终结果, 业务成功, 已持久化 | 本批实现 |

接收方必须先校验并保留, 再回复. 拒绝, 解析失败, 身份或内容冲突不能发出肯定回执. 相同身份和完整内容的重复消息复用已保留事实, 可以再次回复相同回执; 相同身份配不同内容仍须拒绝. 不为回执创建新的 Operation, Attempt 或 Report 身份.

Operation 回执须绑定提交关联键, Authority 运行实例及 Operation; 未来 Authority 生成 OperationId 时应同时回传 SubmissionKey 与原接纳映射. 当前 Console 仍提供 OperationId, 没有 SubmissionKey, 不把该未来契约宣称为已实现. `Pending` 是当前保留请求的观察, 最终 Report 是执行证据, 二者不等于独立即时接纳回执.

Attempt 回执须绑定 Authority/Worker 运行实例, OperationId 和 AttemptId, 不接受仅按 OperationId 的模糊确认. 当前授权重投只能重发原授权的身份和完整内容, 不能把回执超时变为新的执行授权或改派依据.

Report 回执须绑定 Authority/Worker 运行实例, OperationId, AttemptId 和 ReportId. 回执只确认收录, 无论该 Report 是首次采用, 附加证据还是相同证据的重复收录. Report 不得因不是最终结果或已经超过 Console 等待窗口而失去收录资格.

回执缺失意味着交付未确认, 不证明未接纳, 未执行或无效果. 回执到达不等于持久化; 收到回执后接收方仍可能崩溃并失去全部易失性记录. 回执本身不再要求回执, 避免无限确认链.

## Attempt 回执与有界授权交付

严格 JSON `protocol_version: 0`, `kind: "attempt_accepted"`, 字段为 `source_instance_id` (Worker), `target_instance_id` (Authority), `operation_id`, `attempt_id`. 单条最多 4096 字节, 拒绝未知字段, 种类或版本. 发送至 `beamlet/v0/authority/<authority-instance-simple>/receipts`, 使用同 Session 的独立有界订阅. Authority 校验实际路由及原授权的完整身份绑定, 未知或冲突回执不改变状态. 静态绑定不是网络认证.

Worker 必须在 `receive_dispatch` 成功后才尝试回复. 合法重复无论处于排队, 运行还是完成阶段均可重复回复同一接纳事实, 不重复执行; 内容冲突, 容量拒绝或 Draining 拒绝新授权均不回复肯定回执. 回执发送任务与 Report 共享最多 256 个发送槽位, 每次预算 500 毫秒, 满时不回滚原接纳也不积累无界待发任务. Worker 不主动重投回执, 由 Authority 重投原授权触发再次回复.

Authority 新接纳时预留交付容量, 活动原授权最多 256 项, 完整去重记录最多 1024 项. 容量满时在新 Operation 接纳前拒绝, 不产生孤立的新授权. 每份授权最多尝试发送 3 次, 每次预算 500 毫秒, 发送完成后等待 1 秒再决定重投, 另有 5 秒总观察期限. 匹配失败同样消耗次数. 发送任务结束, 回执, Console 查询或 Draining 都不重置期限和预算. 耗尽后释放额外字节与活动槽位, 保留原绑定及未确认观察, 不自动改派或重新授权, 不无限后台重试. 仍可接收迟到的匹配回执.

有效回执停止后续授权重投, 不代表 Operation 完成. 合法 Report 先到时必须先经过 Authority 原有证据校验和保留, 成功后也停止后续授权重投, 不等待迟到接纳回执. 无效 Report 不停止重投. Report 已收录后的迟到回执不回退状态. 已启动的发送任务可能仍完成, 接收方仍以相同身份去重; 不保证撤销已经交给传输层的消息.

Authority Draining 仍在原预算内发送已接纳授权并接收回执和 Report, 不接纳新 Operation. 即使已有接纳回执, 没有 Report 的 Operation 仍保持待定并可导致共同退出期限到达. 同 Node 的 Worker 类型化接纳成功返回直接确认, 不建立多余网络回执或重投队列. Operation 独立接纳回执仍未实现.

## Report 回执原型协议

严格 JSON, `protocol_version: 0`, `kind: "report_retained"`, 最多 4096 字节:

```json
{
  "protocol_version": 0,
  "kind": "report_retained",
  "source_instance_id": "00000000-0000-0000-0000-000000000100",
  "target_instance_id": "00000000-0000-0000-0000-000000000201",
  "operation_id": "00000000-0000-0000-0000-000000000301",
  "attempt_id": "00000000-0000-0000-0000-000000000401",
  "report_id": "00000000-0000-0000-0000-000000000501"
}
```

发送至 `beamlet/v0/worker/<worker-instance-simple>/receipts`, 与 Attempt 收件箱分开, 共享同一 Zenoh Session. Worker 必须同时验证实际路由, 来源和目标运行实例, 以及本地待确认 Report 的全部身份; 未知或不匹配回执不新增记录, 不清除其他待确认项. 相同有效回执去重. 静态绑定校验不是发送方认证, 原型仍限定在受信测试网络.

公共编解码位于 Agent 的可选 `test-support` Adapter, 不是新增纯 Kernel 执行授权消息或稳定 Client SDK. 旧 Report JSON 及 Console 请求/响应保持不变. 目前只编码 Attempt/Report 回执, Operation 肯定回执仍未实现.

## 有界 Report 交付

Worker 先缓存 Report, 再加入本地交付记录. 每份 Report 最多尝试发送 3 次相同内容, 每次发送预算 500 毫秒, 发送结束后最多等待 1 秒回执再决定是否重投. 匹配等待或发送失败也消耗本次发送预算和次数, 计数不是执行授权 Attempt 的数量. 从缓存后首次进入交付记录起另有 5 秒总观察期限; 到期不再启动新发送, 已启动的发送仍受自身预算约束. 到期观察受 100 毫秒检查周期及 Tokio 调度影响, 不是硬实时保证. 不更换 ReportId, 不调用执行器重跑. 未完成执行与活动待确认交付合计最多 256 项, 发送任务最多 256 项. 全部已完成交付记录最多 1024 项, 与当前 Worker 的记录保留上限一致.

确认后保留去重记录, 清理额外待发字节副本; 耗尽发送次数或观察期限后保留未确认终态, 停止自动发送并释放活动交付槽位. 不淘汰记录来重置预算. 重复 Attempt 只能复用原缓存 Report 和既有交付预算, 不延长时间或恢复耗尽次数. 已确认交付不因重复授权再次进入发送队列. 耗尽后仍可收录匹配的迟到回执, 但不自动重新发送. 原始 Report 仍由 Worker 内存账本保留到驱动退出.

Authority 校验并收录 Report 后, 在有界发送槽位中尝试回复回执, 每次预算 500 毫秒. 槽位已满或发送失败不回滚已收录证据, 也不建立无界回执队列. Worker 如重投原 Report, Authority 对合法重复再次回复. Authority 不主动重投回执, 不为回执分配独立可靠投递状态.

## Draining 与本地交付

Worker 正常排空要求已接纳执行完成, 所有已生成 Report 获得匹配的收录回执, 且发送任务结束. 耗尽后仍有未确认项不能宣称正常排空; 等待迟到回执或 Node 的共同 Draining 期限. 到期非零退出, 对外退出观察为 `unconfirmed`, 不生成失败 Report 或 `Effect::None`. 运行期的发送次数/观察期限不会因进入 Draining 或重复消息而重置.

Authority 在 Draining 中仍收录合法迟到或重复 Report 并尝试回复. Authority 正常排空只要求本地收录及已有发送尝试结束, 不等待 Worker 确认已收到回执. 同时关闭两端时可能出现 Authority 已保留但 Worker 未收到回执的情况, 此时 Worker 应保留未确认结论. 不引入 ACK-of-ACK 或隐含关闭宽限期.

同 Node 的本地 Worker 保持类型化交付. Authority 的 `receive_report` 成功返回就是同进程内的收录确认, 不为了回执强制编码或回环网络; 若该调用失败则不能宣称确认. Node 不将一条组合驱动的内部成功推广为远端收录或持久保留.

## 验收边界

真实进程应覆盖: 正常远端回执, Report 或回执丢失后相同证据重投, 非法/错绑定/重复/迟到回执, Authority 对重复和附加证据回执, 耗尽后重复授权不能重置预算, Draining 期间确认和到期未确认. 仍运行现有测试, 本批不新增仓库测试用例. 网络故障下的有限进程验收不是持久恢复或形式证明.
