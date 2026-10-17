# Runtime deadline 终止分类修复

## Goal and authorization

让消费者可靠区分执行预算到期、显式取消和无关 worker 崩溃，解除 Web observation 的 Runtime 回归阻塞。用户先回复“创建”，并在最终规划摘要后回复“批准”，授权按本规划进入实现（2026-10-17）。

这是 Runtime 基线缺陷修复，独立于 Web 产品任务；[observation 独立检查](../10-17-web-observation/research/independent-check.md) 是来源，本任务通过后仍须返回 observation 完成验收。

## Confirmed evidence

- 基线 e7f59d1 和当前候选均已在隔离 VM 的受控 aged-report 实验复现：budget50ms，报告约27ms旧，Gateway 给 worker 约23ms，预算到期导致 shutdown，Coordinator 在自身 deadline 前接受 error/worker_stopped。复现未调用 observation API。
- 源码：executor_gateway.ex:91 将 execution_deadline 转普通 cancel；:145 的 DOWN 生成 error/worker_stopped；:193/:215 扣减 lease age；operation_coordinator.ex:35 独立计时，:94 提前接受完成。路径均在 apps/beamlet_runtime/lib/beamlet/runtime/。
- 已有断言 apps/beamlet_runtime/test/beamlet/runtime_test.exs:87/:91 要求 deadline；Actions.Result 已允许 deadline，无需增加状态枚举。
- composition_test.exs:23/:31 曾在100ms内未收到成功结果；后续通过，但历史原因未证明。不能直接归因于短预算缺陷或认定为已知 flaky。原始失败日志与受控证据见 research/。

## Requirements

- D1：执行预算到期引发的终止保持 deadline 分类，不因先于 Coordinator timer 到达而变成通用 error；终止已观察与未确认必须区分。
- D2：显式取消、无关崩溃、正常成功和基础设施丢失保持可区分；只接受一次匹配终态，已接受成功不被后续 deadline/cancel 覆盖。并发触发不承诺跨 VM 全局时间顺序，具体本地裁决见 design.md 已批准契约。
- D3：保留租约年龄的保守预算扣减、准入/容量计费、取消升级、owner 清理、一次执行及无自动重试。worker DOWN 不代表外部服务终止、回滚或停止计费。
- D4：用确定性有效旧报告场景证明修复与真实 worker 退出；不得靠放宽断言、删除租约扣减或重复运行直到通过掩盖缺陷。
- D5：对历史 composition 超时做有界调查，记录证据、当前结果及仍未知的部分。若发现另一种生产缺陷，先记录并审查范围；不得用本次 deadline 修复冒充其根因证明。
- D6：保留工作区内 observation 改动、既有公共返回结构和依赖边界；不得混入 Web、Agent 或新调度/存储机制。

## Acceptance Criteria

- [x] DA1/D1,D4：有效 aged-report 的实际 dispatch 必须在 Coordinator deadline 前触发 executor deadline；观察 worker DOWN，消费者收到 deadline/worker_stopped，原代码确定性失败、修复后通过。
- [x] DA2/D1,D2：尚未观察终止时保留 deadline/termination_unconfirmed；显式取消已确认退出为 cancelled/worker_stopped，未确认保持 uncertain/cancel_unconfirmed；无关崩溃仍 error/worker_lost。
- [x] DA3/D2,D3：覆盖显式取消与 executor deadline 竞争、成功竞争、kill 升级、迟到/重复完成、owner/基础设施丢失，终态及容量只结算一次且无第二次 dispatch。
- [x] DA4/D3,D6：Runtime 与相邻 Agent/Node/CLI 及全量普通/适用命名分布式门禁通过，记录实际执行数与排除数；格式、warning-fatal compile、Credo、Dialyzer通过，失败证据保留。
- [x] DA5/D5：composition 调查给出证据及明确处置；未复现不能声称根因解决，若仍阻塞须保留待决项，不能静默验收。
- [x] DA6：独立检查通过并同步实际实现契约；返回 observation 复核解除阻塞，不能自动认定它或 Web 父任务完成。

## Out of scope

不增加重试/恢复/持久化，不延长 executable budget，不更改目标选择、报告 freshness、容量政策，不改 provider 外部取消语义，不重做整个 Runtime。提交、分支、归档未获授权。设计与实现计划已获最终规划批准；实现偏离契约时仍须审查。
