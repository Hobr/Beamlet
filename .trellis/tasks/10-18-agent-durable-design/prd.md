# 修订 Agent durable 事实归属与事件恢复设计

## Goal

把本次已确认的 durable 模型写入仓库设计与相关入口，为后续独立代码实现任务提供一致依据。仅交付文档；用户明确允许不考虑旧格式兼容。

## Background

已有 Ecto、Runtime durable、executor journal 及 Agent 消息检查点实现。旧设计文档仍称内存实现且主张检查点主导恢复，与当前代码和新决策均不一致。用户已确认：Agent 不重复保存 LLM/Tool 请求或回复，Operation 拥有确定输入，accepted Result 拥有业务输出。

## Requirements

- R1：明确正文归属、用户原始输入例外、Executor 证据与权威结果之别。
- R2：Agent 以事件归约恢复控制状态，检查点加速；上下文按固定来源策略构建，提交到新的 LLM Operation。
- R3：保留分布式协议、原子准备、单次采纳/消费、不确定性和零自动重执行，解释职责正交的范围。
- R4：更新 fork/导出/图及内容保留，禁止父事件链递归和将继承观察伪装成新执行。
- R5：区分目标设计、当前实现与旧研究；DeepSeek-Harness 仅为用户提供思想摘要，未核验来源。
- R6：同步主设计、验收计划、术语、双语架构入口和 backend spec 指针，提供后续可验证的实施切分。

## Acceptance Criteria

- [x] AC1（R1）：主设计有唯一正文归属表，accepted Result 与 executor final result 明确区分。
- [x] AC2（R2）：归约、检查点和上下文来源契约明确，Agent 无权威 transcript 副本。
- [x] AC3（R3）：本地/分布式 × 内存/durable 可组合；提交缝隙与 unknown 不被隐藏。
- [x] AC4（R4）：fork 保留直接引用闭包，导出/图注明来源、偏序与缺失。
- [x] AC5（R5、R6）：相关入口不将目标当已实现；研究明确被替代决策和证据强度。
- [x] AC6（全部）：文档本地链接和 diff 空白检查通过，无应用/配置/依赖/迁移变更。

## Out of Scope

代码实现、数据库迁移或清理、旧 API/数据兼容、通用 Workflow/Task/Branch 引擎、自动重试/切主、图 UI 实现、物理耐久测试、自动创建后续实现任务。
