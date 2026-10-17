# Runtime deadline classification design

用户已在最终规划摘要后回复“批准”（2026-10-17），以下终止分类契约获准实现。

## Boundary and ownership

只在 Runtime Gateway 的执行终止来源及 Coordinator 的匹配终态处理上修复；源码依据见 prd.md。Gateway 管理 execution budget/worker monitor/cancellation/escalation；Coordinator 管理 operation deadline、对外单终态及取消请求。不把 UI/Node 观测层变成补偿或重分类层。

保留完整 Result 结构、执行身份验证、字节限制、保守 lease-age 扣减和一次 dispatch。Actions.Result 当前已接受 deadline；拟议组合无需新状态枚举。协议对受信的匹配 Gateway completion 处理仍依赖现有 handle/attempt/incarnation 验证。

## Approved terminal contract

| 已观察事实 | 对外结果 |
| --- | --- |
| Gateway execution deadline 发起终止，观察到 shutdown 或其 kill 升级导致的 DOWN | deadline / worker_stopped |
| Coordinator operation deadline 到达，仍无确认终止 | deadline / termination_unconfirmed |
| 显式取消发起终止且观察到相应 DOWN | cancelled / worker_stopped |
| 显式取消未获得终止确认 | uncertain / cancel_unconfirmed |
| 与终止请求无因果证据的 worker 崩溃 | error / worker_lost |
| 已接受正常成功 | 保持成功，后续 timer/取消/完成不可覆盖 |

worker_stopped 只描述本地执行进程已观察退出，不证明外部服务已取消或无副作用。基础设施/连接丢失保留现有 uncertain 契约。

Gateway 为每个实际 admitted attempt 保留最少的终止来源：首次在该 owner 处理的取消触发决定来源，后续触发不得覆写。不要从 worker DOWN 的到达时刻倒猜原因。保留原共享 cancellation 标记及 kill_requested 的因果检查；真实无关崩溃不能因为曾收到 cancel 就一概改成 deadline。

Coordinator 自己的已接受终态始终优先；在尚无终态时，接收合法 Gateway deadline 分类不得被泛化的 stopping=>cancelled 分支改写。跨 owner/VM 不承诺全局先后顺序：若 Coordinator 已先产生终态，其后的 Gateway 数据被忽略。真实成功在首个合法终态被接受前仍沿用既有竞态语义。

## Intended flow

有效 report/lease -> 现有 admission/remaining-budget -> admitted entry 记录空终止来源 -> deadline 或 cancel 触发时原子记录本地首次来源并请求停止 -> shutdown/升级 DOWN 结合来源构造结果 -> Coordinator 验证身份和未终态条件 -> 只接受并发送一次。

不改变 scheduling/lease age/counting 和 worker 退休顺序。优先使用小型私有 helper，避免 Gateway/Coordinator 大范围重构。实现期必须确认 tombstone/late timer 分支安全，不能假定 terminal entry 仍是运行 map。

## Deterministic proof

从现有可运行受控诊断构造测试：实际 valid report 在 eligibility 后变旧但不失效，dispatch一次；保持足够可观测的 executor/coordinator预算差，以同步证据控制而非赌50ms调度。断言实际调用次数、worker monitor DOWN、首终态分类、无二次终态，以及后续 timer 不能覆写。

测试只保留必要状态探针，使用报告源时钟/相对时长，不跨 VM 比较 monotonic时间。测试专用同步不进入公共产品 API。不把因fixture阻塞了admission而未产生worker的实验当作executor deadline证明。

## Composition investigation and acceptance

历史 composition 100ms failure 单独记录。先读取证据，必要时有界追踪一次实际 admission/execution/result，不反复跑到绿；不得单纯增加assert_receive等待或把success放宽。若无复现/根因，提交证据和明确剩余风险供决定，不宣称全部解除阻塞。

## Compatibility and rollback

返回结构不变，deadline/worker_stopped 是新的准确组合，旧错误误分类被更正。同步 Runtime spec 的错误矩阵使 deadline 和显式取消分行。可信分布式 peers 应运行匹配版本；不承诺混合版本下旧 Gateway 自动准确归因。

保留本任务修改前 source/diff边界；撤回仅撤本任务分类修复和新增测试，绝不回滚既有 observation 工作区。无数据迁移或业务undo。
