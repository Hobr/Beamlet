# Node 库实施计划

## Prerequisites

父任务最终摘要需获得用户后续批准，然后仅 start 本子任务。先读父 design.md 及注入 specs；本子任务不因任务创建而自动获准实现。

## Steps

- [x] 快照 git 状态，逐一检索 Node.Application、Node.CLI、:boot、release_integration 的实际调用。
- [x] 加库加载无副作用、宿主显式监督及七角色测试，保留已有生命周期回归。
- [x] 删除 Node Application/mod callback；保留 Supervisor 装配和公开库接口。
- [x] 提取共享 Cluster 校验/连接，测非法名字、未允许项、数量/长度边界、失败连接。
- [x] 原 CLI 客户端/测试/集成 fixture 迁入 CLI；同步 direct deps/test_helper，生成 Application 仍空启动。
- [x] 活跃产品代码引用迁移为共享 Cluster/Agent 或新 CLI.Client，不加旧名转发；旧 deployment release/config/scripts 按批准范围留待 daemon 子任务。
- [x] 更新本步接口说明和 spec，向后续任务交付配置/连接接口。

## Validation and handoff

- [x] mix format --check-formatted；mix compile --force --warnings-as-errors；mix test --seed 631927（169 passed，含2 doctests；14 distributed excluded）。
- [x] 独立命名 VM 的实际 distributed 测试：Runtime6 + Node7 + CLI1 = 14 passed；安全随机 cookie 不回显。初次 inherited ERL_FLAGS 含 -setcookie 导致 handshake 失败；最小 OTP probe 证实 mismatch，改为 parent 显式 --cookie 后 match/连接及全套通过。
- [x] mix credo --strict（迁移 alias 顺序修正后通过）；git diff --check / cached --check 通过。
- [x] 主动 LSP 尝试并记录限制：Pi-lens 部分路径 unavailable；独立 elixir-ls 因自身依赖缺失/锁不匹配且初始化超时，13路径均 inconclusive，未宣称 clean。
- [x] 独立 check：READY，仅限本子任务；无 actionable P0/P1/P2。审查核验完整 diff/保留日志，并用独立 probe 验证 fresh-VM 加载无角色副作用、连接 controller/helper 在 caller loss/deadline 时于远端恢复前实际 DOWN。主会话已接受本库 seam，允许 daemon 下游实施。
- 风险点：固定注册名、Application callback、test_helper 全局 exclusion、CLI direct deps。
- 回滚点：接口迁移完成但尚未替换 release；遇到调用方破坏先停止下游任务，精确撤销本步差异。

## Evidence / frozen handoff

见 `research/implementation-evidence.md`。产品/test/spec 在父会话启动独立检查时冻结。
本 worker 未执行 staging/unstaging/commit，但观察到预期任务差异已被未知 actor 移入 index；已向父会话报告并保留 index。不得宣称 noStagedFiles。
旧 release 门禁、发现/lookup、daemon 宿主及完整 CLI 会话均不在本步验收内，未运行或实现。

## Independent acceptance and remaining workflow

- 独立报告：`/home/kanade/.pi/agent/sessions/--mnt-data-Project-Beamlet--/subagent-artifacts/outputs/c36ffa48-d2c2-4f47-82d1-62506c02f3c1/reviews/node-library-independent-check.md`，主会话已完整读取。
- 普通169（含2 doctests）/实际 named14、format/forced warning-fatal compile/strict Credo 通过证据获复核；未重复全套运行。独立 probe 日志：`/tmp/beamlet-check-load-21szoj80/result.log`、`/tmp/beamlet-check-cleanup-6hlxpbvv/result.log`。
- LSP 仍 inconclusive；冷启动和 helper 生命周期增强是 reviewer-only probe，未宣称为已提交回归。旧 release、Dialyzer/Sobelow 和父任务最终门禁不在此次 READY 范围。
- 3.3 spec 已复核：五份迁移 spec 记录现有契约；补充独立核验与证据边界，不扩大产品范围。
- 3.4 commit / archive 暂缓：用户未授权提交或操作 index，保留 status=in_progress；实现/check 交付完成不等于已提交/已归档。继续已批准的下一子任务不依赖本轮提交。
