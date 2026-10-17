# Observation Execution Plan

## Preconditions

- [x] 用户在最终规划摘要后回复“批准”（2026-10-17）；本子任务作为首个交付获准 start。
- [x] 阅读父设计 §4 和 research/current-capabilities.md，以及本任务 JSONL 中 spec。
- [x] 无前置实现依赖；禁止为 UI 增加数据库或独立 transcript。

## Mutation ownership and staged handoffs

该交付涉及两个可独立测试的 source seams，顺序交给单写入者，不并发写同一工作树：

1. Agent display 阶段：仅 Agent 源码/测试及本任务 research/agent-display-handoff.md；交付 opt-in API、metadata、上下文/活动投影、兼容性和 focused gate。
2. Runtime/Node observation 阶段：仅 Runtime/Node 源码/测试及本任务 research/node-observation-handoff.md；消费第一阶段交接，不重新实现 Agent display，完成公开报告/角色/有界聚合与 focused gate。
3. 独立 trellis-check 覆盖两阶段整体差异、共享安全/生命周期契约及回归；通过后再同步 implemented specs 与最终证据。

父会话保留范围/验收/提交权限；每阶段不得改未分配子任务或引入存储，无法满足契约时先报告。

## Final engineering acceptance

PASS after independent review, approved Runtime repair and spec synchronization. Parent explicitly retained historical composition uncertainty as residual risk; the demonstrated deadline blocker is corrected. See [acceptance](research/acceptance.md) for per-OA disposition and final evidence. Shared contract is available to the next approved Web host/preset child. No commit/archive/status-completed action.

## Earlier verification checkpoint (superseded by final disposition)

Stage A/B implementation and independent review are complete; whole-child acceptance remains blocked. Evidence: [Agent handoff](research/agent-display-handoff.md), [Runtime/Node handoff](research/node-observation-handoff.md), [independent review](research/independent-check.md).

Independent umbrella gate: 221 ordinary tests passed, 29 distributed excluded; existing named Runtime/Node/CLI gate: 27 executed/passed (does not include two Daemon distributed tests). Format, warning-fatal compile, strict umbrella Credo, existing-PLT Dialyzer (no refresh), Sobelow passed. Reviewer strengthened one local failure-reserve fixture; its final focused suite passed 8 tests.

Blocking disposition: controlled candidate and baseline e7f59d1 traces prove a pre-existing Runtime deadline classification defect (Gateway deadline worker shutdown may be accepted as error/worker_stopped before Coordinator deadline). No observation API participates. Business lifecycle repair is outside the approved observation boundary and was not performed. Historical composition 100ms receive failure remains unexplained despite current passing evidence. Do not waive either item based on later successful suites. User authorized creation/planning of the independent [Runtime deadline repair](../10-17-runtime-deadline-classification/prd.md). The user subsequently approved that task's final plan, authorizing its activation and implementation. Observation remains pending repair/recheck; no acceptance, commit or archive performed. Implemented-spec synchronization remains after acceptance per the agreed staged handoff.

Proposed repair boundary for review: Runtime Gateway cancellation provenance / Coordinator terminal classification and focused regression tests; retain conservative lease-age budget reduction, single terminal acceptance, one attempt and no retries. Regression must deterministically use a valid aged report and prove actual worker DOWN, distinguish deadline from explicit cancellation/unrelated crash, and preserve racing success, escalation and late completion rejection. Exact deadline reason must accurately distinguish observed worker termination from unconfirmed external/provider termination. Investigate composition uncertainty with bounded evidence rather than weakening its assertion.

## Ordered work

- [x] 固定旧默认 snapshot/subscription、identity-island 和 CLI 兼容断言。
- [x] 增加纯显示投影与可选安全 metadata 校验；精确预算、entry/activity identity 和截断结果。
- [x] 将 opt-in 投影接入同一 subscribe/ack/合并机制；不在 Server callback 阻塞读取其他进程。
- [x] 增加 Runtime/Node 公共只读入口、源时钟 age 与显式聚合失败。
- [x] 覆盖慢/死 sink、读取挂起、最大尺寸、畸形 metadata、无角色/重启和真实命名 peer。
- [x] 检查零业务 dispatch/无原始状态泄漏；更新已实现核心 spec，提交验收证据供后续子任务使用。

## Validation and rollback

计划执行：mix format --check-formatted；mix compile --warnings-as-errors；mix test apps/beamlet_agent/test apps/beamlet_runtime/test apps/beamlet_node/test apps/beamlet_cli/test；mix credo --strict；mix dialyzer。命名分布式命令及最终全量门禁见父 implement.md，必须记录实际执行数量。

回滚：保留默认接口，撤下可选观察调用。挂起基础设施的生命周期测试应先证明 helper 实际 DOWN 再恢复目标，不能用发停止消息代替证据。未通过本子任务不得让 Web 直接读取私有状态绕过。
