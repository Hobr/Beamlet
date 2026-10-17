# 执行与验收计划

## Phase and gates

当前in_progress。实现及验证证据见verification.md；独立trellis-check已PASS，详见independent-review.md。主会话完成最终规范复核及交付；用户回复“接受”后，旧研究精确清理及引用修复完成，见cleanup.md。

历史实现/验收/清理阶段按用户“不提交”执行。用户在验收和清理后明确要求“提交”，现授权本地stage/commit本次完整变更；不push、不自动归档。旧实验清理已在用户明确接受后完成，未以review PASS替代确认。

## Ordered work

- [x] 1. 最新最终摘要获批准；validate/context/current后start，记录基线及旧研究未跟踪范围。阅读before-dev、全部manifest/spec和design，不重做已经完成的生态调研。
- [x] 2. 单一implement writer实施Discovery固定erpc/本地有限读取，移除Endpoint源码和两处装配，保留公有API/静态错误/128及字节上限。先完成行为和相关测试，不留双协议兼容分支。
- [x] 3. 替换依赖offer/controller/lease内部细节的Agent/Node测试；用产品测试helper/真实peers验证新有限尾部执行、异常隔离、同名/ID复用/Ref、聚合并发/预算/partial。不要用旧研究脚本当生产回归。
- [x] 4. 复核Node.Agents最少适配，入口已连接筛选、总deadline/并发/结果上限。检查所有七角色组合、CLI/daemon和依赖加载无副作用。
- [x] 5. 同步spec/当前用户文档及必要旧任务supersession说明。原研究结论保持历史边界，代码量/模块/状态机对照写入新任务verification.md。
- [x] 6. 运行合适质量门禁并独立trellis-check，检查输入安全/故障隔离/真正远端结束/晚回复、资源上限和报告一致性。问题修复后只按实际改动重跑。
- [x] 7. 加载update-spec做最终一致性复核；对用户交付实现结果和检查证据。AC1–AC6可按证据勾选；AC7等待用户明确确认完成。不commit，不删旧results/experiments，不自动archive。
- [x] 8. 用户明确确认完成后，按design第8节限定清单删除旧results/experiments/专用.gitignore，更新研究留存摘要/路径说明并审计失效链接。没有确认继续保留。
- [x] 9. 清理差异/测试引用检查通过后报告清理结果和保留内容，勾选AC7。整个任务不提交。

## Validation

从根运行。具体命令须在执行前核对现有test tags/脚本，记录实际命令/执行数量/退出码/工具失败，禁止计划冒充通过。分布式测试使用独立cookie与unique命名、低scheduler；cookie不记入文档/log；控制用standard_io，不连接已有节点。

```bash
python3 .trellis/scripts/task.py validate .trellis/tasks/10-17-simplify-agent-queries
MIX_ENV=test mix compile --warnings-as-errors
mix format --check-formatted
mix test apps/beamlet_agent/test apps/beamlet_node/test apps/beamlet_cli/test apps/beamlet_daemon/test
mix test
mix credo --strict
mix dialyzer
git diff --check
```

- named VM运行discovery_distributed_test，显式include distributed/resource（检查其helper默认排除），必要时使用已有部署/角色集成入口验证宿主。记录实际执行数，不能把默认excluded当通过。
- 十个慢节点用低scheduler/有限并发，允许CI负载时合理时序余量但不得放宽业务预算。暂停/trace/退出测试使用finally清理，不依赖一个固定sleep证明worker已死。
- 主动LSP changed paths检查作为附加诊断，超时/无服务不冒充clean，编译/测试为主要依据；缓存空不是无错误证明。
- 若当前工具/PLT不可用记录阻塞，按spec要求处理；不擅自更新依赖或全仓无关格式。
- 保留新产品验证的简洁摘要和日志位置，不复制旧研究约2MiB证据到新目录作为“清理”规避。

## Review contract

独立checker检查全部受影响Agent/Node/host/spec；检查erpc异常不泄漏、无新监督耦合、远端有限预算独立于客户端timeout、无错误的瞬时取消/绝不重连声明、已删Endpoint无活引用。
检查旧协议256容量是已删除协议的计数，不以新增全局准入服务补回；本任务仍保证单聚合8并发和查询/结果边界。
研究raw/脚本在用户确认前必须仍存在；checker不得为满足AC7提前清理。

## No destructive rollback

只定向恢复本任务产品变更，不git reset/clean、不覆盖用户改动、不删其他任务。
实现/检查若发现需要新的产品行为取舍，回规划；局部命名/测试适配可直接按已批计划执行。

## Implementation evidence

Steps1–5 completed: baseline HEAD9657d2a with only the two untracked task directories;
curated context and before-dev read; finite Discovery entry/erpc implemented;
Endpoint and both registrations removed; durable Agent/Node peer/resource regressions
replace transport internals; all seven roles now assert the discovery capability;
Node.Agents requires only a connection-contract moduledoc update; aggregation logic is unchanged. Specs/README and historical task
supersession notes synchronized. See verification.md for historical exits, counts,
failures and code reduction. The user subsequently requested removal of remaining
intermediates; logs, command records, named launchers and hash inventories were
cleaned, while final summaries and product tests remain. See cleanup.md.

Step6: independent trellis-check PASS; nine actual named discovery/resource tests,
42 focused tests and15 lifecycle tests passed; compile/format/strict Credo passed.
Independent named shell exit was not captured; successful ExUnit summary and process
cleanup were observed. One nonblocking reader-PID assertion was strengthened by the
parent and its focused regression passed (1 passed/6 excluded, exit0).
Step7: parent applied update-spec final consistency review: public/fixed internal
signatures, static errors, finite budgets, failure isolation and approved reconnect/
abandonment semantics match source, README and backend specs. Parent active LSP
probe on four production files timed out for all four; inconclusive, not clean.
Steps8–9/AC7 completed after the user's explicit acceptance on2026-10-17.
Removed only old research results/, experiments/ and dedicated .gitignore; retained
historical conclusions/sources/review and repaired deleted-path references. See
cleanup.md for counts and checks. No staging/commit/archive.
