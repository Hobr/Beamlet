# 简化 Agent 查询实现与故障隔离

## Goal

基于已完成并独立复核的查询传输研究，减少开发者需要维护的自定义查询协议和生命周期状态机，让查询低扰动、可理解、可测试，并避免查询故障终止 Agent。

## Background and Evidence

- 来源：用户明确要求新建实现任务、不提交；新任务经用户确认完成后才清理本次实验中间文件。
- 前置研究：../10-17-query-transport-research/research/report.md、ecosystem.md、quality-review.md。两轮完整实测各98场景/98清理，研究独立检查PASS；这些是研究证据，不是当前产品已经迁移的证明。
- apps/beamlet_agent/lib/beamlet/agent/discovery.ex 目前维护 offer/confirm、alias、challenge/heartbeat 等自定义协议；authority_supervisor.ex 将 Endpoint 放在身份岛 one_for_all 中，端点崩溃可终止现有 Agent。
- apps/beamlet_node/lib/beamlet/node.ex 在非authority角色也启动 Endpoint；node/agents.ex 保留可信已连接目标筛选及有界聚合。
- 现有 Agent.start 已使用 erpc；但发现接口规范目前要求逐消息无自动连接和失联快速回收。不能把改用标准OTP的较弱语义静默宣称等价。

## Requirements

- R1：采用 OTP `:erpc` 与有限的 authority 本地只读函数替代自定义 Endpoint；移除 offer/confirm/challenge/heartbeat/lease 协议及其常驻端点，不为查询引入新社区依赖或通用RPC框架。
- R2：查询只读；查询异常、超时、客户端退出不终止或重建 Agent，不改变模型绑定、历史、turn或业务状态。查询实现不得因其自身进程异常通过监督耦合杀死 Agent。Registry/authority自身损坏的原身份失效语义保持。
- R3：保留 Agent.list/lookup 和 Node.Agents.discover 的调用接口、authority+ID/PID/incarnation真实性、descriptor替换检查、同名区分、静态错误和部分结果；不伪造Ref、不自动重绑或业务重放。
- R4：保留可信节点输入与校验、5秒本地接收预算、最多5秒远端读取预算、32节点/8聚合并发/每authority128身份/1MiB结果上限及敏感信息隔离。用户已接受：调用方超时或退出后已发出的只读工作可在远端有限预算内完成；调用前筛选已连接可信节点，检查后断线允许OTP默认重连，不要求逐消息绝不建连。不再保证失联约300ms回收或过期请求绝不启动，不承诺即时取消或撤回已入业务邮箱的消息。Endpoint专用256 offer/controller配额随该协议移除；不新增全VM查询准入服务，聚合并发限制保持。
- R5：更新受影响的标准测试、角色装配、文档和spec；用长期保留的产品回归测试覆盖新契约，不让产品验收依赖待删除的研究脚本。
- R6：实现、验收与清理阶段遵照用户“不提交”，不stage/commit/push；先交付再等用户确认完成后清理，检查通过不替代用户确认。后续用户明确要求“提交”时，授权本地stage/commit，仍不push。
- R7：清理范围只限旧研究任务 ../10-17-query-transport-research/ 中实验中间文件，明确包含 results/ 与 experiments/ 的脚本、日志、原始记录、派生索引和源快照；保留最终研究结论、生态来源和独立复核摘要，修复失效引用并如实注明原始证据已依用户要求清理。不把摘要假称成仍可读取的原始证据。尚未触发清理门禁前全部保留。

## Acceptance Criteria

- [x] AC1（R1）：新查询实现显著减少原自定义状态机/特殊进程/维护入口，无新依赖，文档解释最终调用和失败路径。
- [x] AC2（R2）：真实本机/远端测试证明查询失败和查询执行进程退出不杀既有Agent；PID/incarnation及可读状态保持一致；原Registry丢失的身份失效回归不被弱化。
- [x] AC3（R3）：list/lookup/attach、同名authority、ID复用/旧descriptor、非authority/缺失/不可达/部分结果的回归通过。
- [x] AC4（R4）：接收/远端读取/并发/结果上限有验证；超时、调用方退出和断线测试符合用户选择的语义，晚回复不污染调用者；不把有限后台只读完成误报成即时取消。
- [x] AC5（R5）：Agent/Node与依赖发现的CLI/daemon角色装配相关测试通过；规范、实际实现和文档一致，生产回归不依赖旧experiments/results。
- [x] AC6（R6）：新任务交付时未发生git提交；用户确认完成前旧研究中间文件仍在，清理处于单独等待门禁。
- [x] AC7（R7）：仅用户确认新任务完成后，执行精确清理清单，results/与experiments/不存在，最终研究摘要/来源仍在，保留文档无误导性失效链接；清理后验证差异范围。

## Out of Scope

新增分布式注册中心、业务Agent持久化/迁移、模型/Runtime执行生命周期重构、业务自动重试、全面更改VM连接策略、第三方依赖引入、物理跨机部署。任何额外范围需另行批准。

## 归档记录

用户在验收、清理和提交完成后明确要求“归档”。实现提交为2735879，后续格式提交为dafaa8f。本次仅归档simplify-agent-queries，保留全部最终任务文档；前置研究与其他任务状态不变。任务直接在dev开发、未建立PR，使用归档命令支持的--skip-branch-validation保留真实分支信息。下文未提交/未归档叙述记录各阶段的历史边界；当前最终状态以task.json为准。

## 最新提交授权

验收及两轮清理完成后，用户明确要求“提交”，授权将本次代码、测试、spec与保留的研究/任务记录一起本地提交；此前未提交的叙述为对应阶段的历史事实。此次不推送、不自动归档。

## Confirmed Decision and Planning Status

用户已明确接受标准OTP语义及检查后断线允许默认重连，具体要求见R4，无待定产品问题。
最终规划已获批准并进入in_progress；唯一writer已完成实现候选及产品验证，证据见verification.md。
AC1–AC6已获实现及独立trellis-check PASS证据；主会话完成规范一致性复核，并补强非阻塞读者PID断言且定向回归通过。详见independent-review.md及verification.md。
用户已于2026-10-17明确回复“接受”，确认本次实现验收；随后按限定范围清理旧研究results/、experiments/和专用.gitignore，修复引用并保留结论/来源/独立复核摘要，AC7已完成。用户随后追加“清理其他中间文件”，当前实现任务validation/、independent-evidence/及3个本会话临时文件也已按明确来源清理，最终摘要与产品测试保留，详见cleanup.md。未提交、未自动归档。
