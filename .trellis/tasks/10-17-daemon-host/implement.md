# Daemon 实施计划

## Prerequisites

node-library 已交付并通过 check；先确认本子任务 status 为 in_progress，再写代码。读取父 design.md 及本任务上下文。

## Steps

- [x] 添加 direct deps；实现 daemon 配置归一化/校验和启用开关。
- [x] 覆盖默认双角色、两个 only、拒绝 interaction/空/重复角色；使用同一编译代码，断言实际进程树。
- [x] 应用显式监督 Node；测试普通 umbrella 启动无服务/连接副作用。
- [x] Node 就绪后执行一次有界 peers 连接，测试失败仍本机可用，清理启动 helper。
- [x] 根 release/build selector、独立 daemon runtime config、env 模板和可信示例迁移，删除旧 release/:boot 配置。
- [x] 更新复制闭包和命名服务检查、runbook；保留原端口碰撞回归和 Web secret 限制。
- [x] 运行并记录复制产物三种方案的 start/RPC/stop 和确定性 authority→executor 流程。

## Validation

- mix format --check-formatted；mix compile --warnings-as-errors；mix test --seed 631927。
- 命名 distributed 相关回归，安全 cookie/唯一 VM 名称；mix credo --strict；主动 LSP 变更路径。
- BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite。
- bash scripts/deployment/check-release.sh（此阶段 daemon 检查；CLI 子任务再扩展），检查 copied .rel/.app/lib，不只 eval。
- 普通 Web missing-secret 行为、Web CSP 保持；git diff --check。
- 风险文件：mix.exs、runtime 配置、rel/env.sh.eex、check-named-release.py；任何启动冲突停止本步精确回滚，不扩大成全局命名重构。
- check 通过后交付相同 artifact 的三个启动方案和 daemon 接口；两产物最终门禁在 CLI 子任务完成。


## Implementation evidence / handoff

- [x] 当前候选实现完成并冻结 product/test/spec，证据见 `research/implementation-evidence.md`。
- [x] 实际验证：171 ordinary（含1 doctest），16 actual named distributed；format、forced warning-fatal compile、strict Credo、daemon build 和同一复制产物三方案 named/RPC/pid/stop/remote turn 通过。
- [x] Web missing-secret 预期失败及现有7个 Web/CSP 测试保持；runtime11类拒绝无 synthetic sentinel 泄漏。
- [x] 主会话独立只读 check 完成；初次发现 F1/F2，修复后最终 READY，主会话接受本子任务交付（见下方最终验收）。
- [ ] 主任务最终两产物/CLI stdin/reattachment 门禁（后续 cli-host）。
- 主动 LSP：10个当前 Elixir 路径初始化超时/工具自身依赖失败，**inconclusive**，不宣称 clean；启动脚本自行尝试 Mix.install 后被限时终止，未主动修复/安装依赖或改动项目版本。
- 既有 index 被未知 actor 更新；本 worker 没有 stage/unstage/reset/commit，保留全部既有及新 staged 内容，`noStagedFiles=false`。详细前后指纹/日志见证据。

## Independent-review repair candidate

- [x] F1/P2 self-fix verified: Node common Limits.new preflight for every role set; direct authority-only malformed-limit Node/daemon errors and copied static Config.Reader rejection before role startup.
- [x] F2/P2 self-fix verified: independent remote-service cleanup with bounded fallback/log closure, original-error preservation and four bounded Python regression tests.
- [x] New candidate frozen;62 affected ordinary +2 named daemon tests pass, Python4 pass, format/forced warning-fatal compile/strict Credo/build/copied three-mode+remote+12 rejection checks pass. Exact new fingerprints/logs and preservation evidence: `research/repair-evidence.md`.
- [x] Parent independent repair recheck: F1 与双服务清理已验证；残留 nested-note 丢失经后续修复及最终独立检查解决。
- Original implementation evidence above remains historical. Current shell script formatting explicitly selected by parent; old recovered/frozen evidence preserved. No product/test/spec edits after new freeze without authorization. Parent cumulative static/integration gates remain pending; LSP remains inconclusive.

## Residual F2 diagnostic repair

- [x] Self-fix verified: preserve nested cleanup notes when transferring service errors to the final primary; original exception identity and independent bounded cleanup unchanged. Existing four Python tests plus two composed RPC/both-service fallback-failure cases pass (6/6); exact independent probe now passes.
- [x] Deployment README explicitly states Python 3.11+ prerequisite (validated on 3.14.7); no provisioning changes. Same22-path candidate frozen; unchanged1003-file release artifact and index verified. Exact before/after logs, hashes and preservation: `research/cleanup-diagnostics-evidence.md`.
- [x] Parent independent diagnostic-repair recheck **READY**;主会话已接受 daemon 交付，允许按批准顺序启动 discovery。No broader Elixir/build/copied gate rerun for note-only correction; prior evidence stays historical.

## Final independent acceptance

- 主会话完整读取最终报告：`/home/kanade/.pi/agent/sessions/--mnt-data-Project-Beamlet--/subagent-artifacts/outputs/273eb355-89ef-4bf8-98a9-ca43a487cbe7/reviews/daemon-cleanup-diagnostics-final-check.md`。F1/F2 均 resolved，无 daemon-scope blocker。
- 独立实际执行 Python6 项和原失败 probe 均通过；22/22 候选及1003/1003产物文件/清单匹配。最终产品 manifest SHA256 `13afbf11e88c485e38cb0b92fa266092cbc7b2200d74be32b0abbdffc6f62eb9`；产物内容 manifest `08cdf56b28a7064764952c620f682495d207e4d921604e98e82a8e56d4914eaf`。此后主会话仅追加验收/spec 状态，不修改产品。
- 62 affected ordinary/2 actual named、重建 copied 三模式/remote/12拒绝证据与初次171 ordinary/16 named/HTTP/Web证据保持各自执行范围，不宣称本轮重复全套。
- 3.3 spec 已复核并记录共用 limits 预校验、独立清理和嵌套错误可见性；Python3.11+文档化。LSP仍 inconclusive；父任务 Dialyzer/Sobelow/xref/最终双产物stdin/reattach门禁待完成。
- commit/index/archive 未获授权，保持 in_progress 和现有 staged 内容，不自动提交/归档。实现与独立验收完成可以向下游交付，不等于父任务完成。
