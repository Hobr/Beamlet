# CLI 实施与最终 release 集成

## Prerequisites

前三个子任务已交付接口并通过检查，先读取父/子设计和 specs，再 start 本子任务。不得为赶进度绕过 final planning approval。

## Steps

- [x] 保留已有 Owl/ucwidth 依赖但不开发全屏 TUI；补齐 Node/Agent direct deps。
- [x] parser/dispatcher/renderer/session及IO注入，覆盖 help/connect/nodes/agents/create/attach/input/status/watch/stop/close/detach/quit。
- [x] 建立可信 creation-options 示例；限制 alias/节点/命令/输出，所有错误投影不带 key/binding/raw异常。
- [x] 复用查询/lookup和真实 Ref；验证重名、多客户端、detach/EOF/quit 不关闭 Agent，旧别名不静默重绑。
- [x] standalone release runner 在应用启动后进入 stdin 循环；普通应用启动不读取 stdin或启动 Node，测试不 halt VM。
- [x] 添加 CLI release/cli_runtime 配置；更新 shared env模板/示例/runbook/检查脚本并清理旧调用。
- [x] 同一 daemon copy 以3配置实际 start/RPC/stop；复制 CLI release 以两次独立 stdin 会话完成创建→退出→再次查找附着→操作/关闭。
- [x] 保留真实 HTTP→workspace→模型、错误环境/no fallback、stop/loss/no replay 与原 watch 生命周期回归。
- [x] 同步当前 backend spec，回到父任务逐项验收AC1..AC9；请求最终 check 全范围而非只检查最后一批文件。

## Validation

执行父 implement.md 的完整命令清单：format/compile/tests/实际 named distributed/严格 Credo/Dialyzer/Sobelow/xref、两个后端 release、copied/named 检查和 check-local。
保留Web缺secret及CSP检查；主动LSP变更路径，不将超时当通过；记录实际日志、测试数、build/hash、已有PLT与刷新区别。

风险点为 runtime config、CLI Application/Runner、watch sink、Session引用、root release和Python/Shell检查。release复制测试需真正无源码/deps、终端由stdin驱动，不只eval/import模块。

## Rollback and finish

若CLI失败不更改Agent权威位置或加业务自动重试补救；保留diff并精确回退该步。最终检查通过后提出分组提交计划请用户确认；不自动push/amend。父任务仍是集成协调，不为写实现代码切换到父任务 start。

## Current user steering and integration fixes

- Reuse installed Owl0.13.1 tables/output/display utilities; retain only bounded
  transport and application grammar/dispatch/identity/sanitization code.
- Repeat affected tests/static/LSP and rebuild both artifacts after this revision;
  earlier copied smoke counts/hashes are historical until new candidate passes.
- Existing-PLT Dialyzer initially reported3 private Node.Agents MapSet opacity
  warnings; forced compile was byte-identical and force-check reproduced them.
  Narrow private MapSet.t annotation under investigation, no protocol change.
- Independent CLI repair check returned READY; parent AC1–AC9 accepted. Commit/archive remain deferred.

The private MapSet.t annotation did not resolve Dialyzer's opaque warnings. Final
validator uses a list of at most32 seen atoms, preserving identical duplicate,
proper-list and target validation. Existing-PLT Dialyzer then passed with zero
errors. No warning suppression, public/protocol or dependency change occurred.

Historical initial gates:165-path source,191 ordinary/23 named; retained in
research/implementation-evidence.md. Independent review then BLOCKED3 CLI findings.
The separately frozen166-path repair passes196 ordinary/23 named and received
independent READY. Final full aggregate exit0, fresh exact-byte PTY/copied/live
probes, hashes and parent acceptance are summarized in research/review-disposition.md
and ../10-17-node-host-split/research/final-acceptance.md. Only acceptance/spec
 documentation follows that frozen code candidate; no commit/archive/journal action.
