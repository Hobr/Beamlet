# Execution approval and lane ownership

## Approval receipt

用户在包含目标、范围、非目标、验收、风险与全部规划文件的最终摘要之后回复“确认”。这构成实施批准，而非仅创建任务批准。首先执行 node-library，其余步骤按既定顺序并通过独立 check 后交接。

## Latest commit authorization

最终验收后，用户要求进一步拆分提交，并对9组方案回复“确认”。这一后续授权允许精确暂存/提交本任务文件，取代下文历史阶段的 commit 待授权状态；不允许 push/改分支/归档/journal。实际提交及临时快照验证见 research/commit-execution.md，未知 .gitignore 改动保持排除。

## Baseline and safety (historical before commit approval)

- Repository/cwd: `/mnt/data/Project/Beamlet`, branch `dev`, baseline commit `0fed1b1`。
- 实施前已有32个 staged 规划文件，无 unstaged 差异。原始 staged diff SHA256: `a081578c3c577efd7ab6b42bb4712d4323337b3f8814190631af5174cf048dfc`。
- 禁止重置、覆盖或提交已有 staged 内容；本轮没有提交/push授权。
- 当前 checkout 不是 clean，不创建 managed worktree；采用同一 cwd 串行单写者。父会话在 worker 活跃期间不改其代码/测试/spec。

## Topology and lane board

总体为 multi-seam，已按四个独立子任务拆分；不能把整项需求一次交给同一实现 worker。子任务依赖与验收见父 implement.md。

| Lane | Scope / exclusive contract | Isolation / writer | Next gate | Durable handoff |
| --- | --- | --- | --- | --- |
| node-library | library/host seam：Node 自启动移除、Cluster 共享接口、原终端适配器及引用/测试迁移 | 实现与独立只读 check 完成；主会话接受 READY | 169普通/14实际named及独立检查通过；commit/archive 待授权 | 子任务 implement.md / research/implementation-evidence.md / 独立报告 |
| daemon-host | 宿主启动与 daemon release | 实现/F1/F2修复及最终独立 READY 已接受；commit/archive 待授权 | 同产物三模式/remote/12拒绝与Python6回归、独立身份验证完成 | daemon implement.md / research证据 / 最终独立报告 |
| agent-discovery | authority 查询与共享聚合接口 | 实现/P1准入修复及独立 READY 已接受；commit/archive 待授权 | 独立12定向/7实际named、超时后零新增查询与256混合配额通过 | discovery research/review-disposition.md / 独立报告 |
| cli-host | CLI 会话与 CLI release / 跨宿主集成 | 实现/3项修复及独立 READY 已接受；commit/archive 待授权 | 196普通/23实际named、真实PTY/双产物/分页/特殊ID/Ref重附着通过 | CLI research/review-disposition.md / 最终独立报告 |
| integration | 父任务仅对已交付接口做最终验收、汇总与提交提案 | 主会话，所有 child 写者已结束 | 父AC1..AC9已验收，待提交授权 | research/final-acceptance.md / 父implement |

node-library 采用单一写者的理由：这是一次既有 library/host seam 的迁移，旧 CLI 提取、共享连接调用与 test/deps/test_helper 的 namespace 迁移相互依赖；再拆为多个并发写者会争用同一旧模块和调用方，并产生不必要的临时兼容实现。只交付该 seam，不让该 worker 同时实现 daemon、Agent 查询或完整 CLI shell。
