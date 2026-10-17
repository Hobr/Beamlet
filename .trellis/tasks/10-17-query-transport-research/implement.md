# 执行计划与历史进度

## 留存状态与后续门禁

2026-10-17，用户明确接受后续simplify-agent-queries实现，已触发约定的研究中间文件清理。本任务results/、experiments/及专用.gitignore已删除；原始JSONL、失败记录、源快照、日志、脚本与逐命令退出码不再随仓库提供。本文件是执行历史摘要，不提供失效复现命令，不把摘要冒充原始证据。不提交或自动归档，不更改研究任务状态。

## 已完成的研究工作

- [x] 1. 研究规划批准并激活，基线9657d2a；隔离本机临时VM，不接触生产集群。
- [x] 2. 核对OTP29.1.2/ERTS17.1.1/Elixir1.20.4及安装源码路径/哈希；证实现代rpc.call委托erpc，传统rex使用版本锁定内部探针。
- [x] 3. 完成OTP、现Endpoint、gen_rpc/Syn/Horde/libcluster的一手生态比较；不安装第三方库，不声称兼容实测。
- [x] 4. 实验使用真实authority/Server、standard_io独立控制面、私有epmd、低scheduler与有限进程组watchdog。
- [x] 5. 原最终run20261017T122252-5c3d06fc：98场景、98peer清理、205行、final passed；关键组合各3个新peer，另含控制与96查询批次。
- [x] 6. 真正kill Endpoint，确认one_for_all连带旧Agent死亡；显式重建后PID/incarnation变化。普通查询超时/调用方死亡是不同故障。
- [x] 7. 完成report/experiment-findings/otp-paths/ecosystem；区分响应放弃、worker停止、队列撤回、准入和连接语义。
- [x] 8. 独立full复跑20261017T124152-6fd7b540：compile退出0，实验退出0/125814ms；同为98场景/98清理/205行/final passed。新summary/审计通过，与原run连接分类一致。迟到邮箱采样起点描述已修正。
- [x] 9. 主会话核读独立PASS并交付；用户批准后续有限local/erpc实现，现已接受验收，按其限定清单完成本研究中间文件清理及引用修复。无stage/commit/push/archive。

## 保留结论与验证边界

最终结论见[research/report.md](research/report.md)，独立历史复核摘要见[research/quality-review.md](research/quality-review.md)。官方来源及源码语义分别见ecosystem.md、otp-paths.md。后续产品行为与实际产品回归见[新任务验收](../10-17-simplify-agent-queries/acceptance.md)，不得用历史98场景代替产品验证。

历史研究期执行过脚本显式format、warnings-as-errors compile、既有Discovery9 passed/seed631927、JSONL语义/Python语法/空白链接/范围审计。独立review只重跑一次full，不另跑产品测试。原逐命令日志已清理，目前不能按原入口复现。

早期失败涵盖Elixir application启动、improper alias JSON编码、过强连接断言；未trace的nodeup发送者始终没有根因定论。6dc6bbae工作流在最终handoff阶段超时，恢复阶段先读取原证据而非重跑，后续独立review才真实复跑一次full。原失败与成功证据一并清理，不选择性保留有利raw。

历史进程审计记录所有owned peers/helpers退出、私有epmd停止，未触碰共享epmd或语言服务器。最终coordinator有一条peer退出nodedown通知，批次邮箱空是另一观察窗。跨物理机/丢包/半开/生产性能/长压力/即时取消/队列撤回/outer重启强度耗尽均未验证。

## 清理范围

仅删除本任务results/、experiments/与专用.gitignore；保留prd/design/context清单及research文档，不改全局忽略规则，不删其他任务、构建目录或全局代理产物。清理后仅保留历史事实和来源，不承诺恢复已删除的原件。
