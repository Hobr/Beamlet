# Runtime deadline repair execution plan

## Phase and prerequisites

- [x] 用户批准创建并规划独立任务（“创建”）。
- [x] 核对 Gateway/Coordinator、现有 deadline/composition 测试和 Actions.Result 状态契约。
- [x] 建立 PRD、拟议设计、执行计划及双 context manifest。
- [x] 用户在最终规划摘要后回复“批准”（2026-10-17），准许 task.py start 并进入实现。
- [x] activation后记录完整dirty diff和untracked清单，确保保留 observation 改动（/tmp/runtime-deadline-start）。

## Engineering acceptance

Implementation and independent review passed; parent explicitly dispositioned historical composition as unresolved residual risk and synchronized Runtime/error/quality specs. See [acceptance](research/acceptance.md). Return to observation for its separate acceptance; no commit/archive or task completion status change.

## Single-writer sequence

1. trellis-implement 读取 manifests -> prd -> design -> implement 及已保留诊断/失败日志；把受控机制变成确定性失败回归。
2. 按批准契约最小修改 executor_gateway.ex / operation_coordinator.ex 与 Runtime focused tests，先验证错误分类被修正，再验证竞争/清理不变量。若不需要改某一模块，保持其不动。
3. 有界调查 composition历史失败，独立记录归因证据和未解风险；其他生产根因或超范围修复先报告，不扩大本任务。
4. 独立 trellis-check 覆盖修复增量并结合 observation既有改动验证；机械修复后重跑受影响检查。不得用后续绿色门禁抹掉初始缺陷。
5. 通过后按 trellis-update-spec 同步 operation-runtime / error-handling / quality 中实际终止契约与回归教训；observation spec同步仍归原任务。
6. 返回 web-observation 做阻塞处置与验收复核，再继续 Web交付；commit/archive等待另行授权。

## Verification

- focused deterministic aged-report regression：未修复时失败，修复后通过；覆盖真实DOWN、单dispatch、单终态、cancel/deadline/crash/success/kill/late/owner loss矩阵。
- mix test apps/beamlet_runtime/test apps/beamlet_agent/test apps/beamlet_node/test apps/beamlet_cli/test --seed 631927
- mix test（记录每app计数及excluded）
- 使用隔离命名VM和临时测试cookie执行 Runtime/Node/CLI --only distributed；断言真实执行数量。日志不得包含cookie。物理多主机不在验收内。
- mix format --check-formatted；mix compile --warnings-as-errors；mix credo --strict；mix dialyzer（区分已有PLT与refresh）。活跃LSP不可用/超时记inconclusive。
- git diff --check；与起点dirty清单比较防止覆盖其他改动。
- 仅因新修改/失败/未解风险重跑所需检查，不重复无关资产/release构建。

## Evidence and stop points

research/保留review、受控trace脚本/候选与基线日志、原始deadline/composition失败。测试fixture使用临时observer身份，不写产品日志或持久化执行历史。后续失败日志使用新文件名。

涉及Result状态/原因、终态竞争规则或取消/lease策略的偏离需要回到规划。基础设施失败停止并报告，不换CLI/provider绕过。

## Rollback

只撤本任务对Gateway/Coordinator及自身tests/spec的修改，保留Agent/Node/Directory observation增量和未跟踪文件。回滚不代表已执行业务被撤销。当前分支dev未授权改变。
