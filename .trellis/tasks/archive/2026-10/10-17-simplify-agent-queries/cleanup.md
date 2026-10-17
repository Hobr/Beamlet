# 用户验收后的中间文件清理

2026-10-17，用户在技术验收交付后明确回复“接受”，触发design第8节及PRD R7的清理授权。AC7完成；不自动提交或归档。

## 精确范围

删除且仅删除旧任务10-17-query-transport-research中的：

- results/：55个文件、1,928,219字节，包含成功与失败的原始记录、日志、派生索引、源快照和审计脚本。
- experiments/：4个文件、45,267字节，包含实验入口与helpers。
- 专用.gitignore：仅服务旧results目录的两条例外，不改root或全局忽略规则。

共删除59个实验文件及1份专用忽略文件；未复制原始证据到新任务、其他目录或全局artifact作为留存替代。未删除其他任务、构建产物或全局代理artifact。

保留研究prd/design/context清单与六份research文档。report、experiment-findings、otp-paths保留结论与限制；ecosystem保留官方来源；quality-review保留独立历史PASS摘要；current-evidence保留规划时观察。修复旧证据Markdown链接并移除失效复现命令，显著标注原始记录和脚本已清理。摘要不是可重新读取的原始证据，也不提供精确复现承诺。

原run20261017T122252-5c3d06fc与独立run20261017T124152-6fd7b540均为98场景/98清理、final passed，运行时OTP29.1.2/ERTS17.1.1/Elixir1.20.4；这些是历史事实摘要，不替代新产品验收。早期失败的nodeup归因仍未证实，物理网络/长期压力等限制保留。

## 检查

检查两目录与专用忽略文件不存在；两任务保留Markdown的本地链接、空白及代码围栏；任务JSON/JSONL语法与context validate；所有apps下Elixir源码/测试的清理前后SHA256；产品对已删研究路径无依赖；Git空白、HEAD和索引状态。

本轮只删除研究中间文件并更新研究/任务文档，未修改产品代码，不重复运行已经通过且代码未变化的产品测试。最终HEAD9657d2a、索引为空；无stage/commit/push/archive。此前技术验收及实现/独立检查记录保留其各自的历史观察时点。

执行中首轮链接审计发现本记录尚未创建，导致acceptance.md对cleanup.md引用暂时不存在；本记录创建后重新执行完整审计通过。

## 用户追加要求：清理其他中间文件

用户随后明确要求“清理其他中间文件”，扩展了先前仅旧研究目录的清理范围。本轮仅处理当前实现任务及本会话确实创建的临时文件：

- 当前任务validation/：38文件，98,485字节，包括日志、命令记录、两个named启动脚本、源哈希索引及生成的handoff数据。
- 当前任务independent-evidence/：10文件，14,796字节，包括独立检查日志、命令及进程/范围记录。
- /tmp下beamlet-named-all.exs、beamlet-named.exs及beamlet-cleanup-product-hashes.json：3文件，15,111字节。两个临时启动脚本先与任务副本核对等价；哈希清单为前次清理创建。

本轮共删除51文件、128,392字节。没有清理其他任务、构建缓存、全局代理会话/交接artifact。最终verification.md、independent-review.md、acceptance.md及研究来源保留；去除已删路径的可点击链接和启动命令，如实标注原日志/哈希/命令记录已不存在。成功与失败历史摘要均保留，不把摘要当成原始证据。

删除前后以本会话哈希清单比较全部apps下Elixir源码/测试，完全一致，随后删除这份临时清单。最终检查两任务保留文档本地链接、空白、代码围栏、JSON清单和context validate；确认删除目录/临时文件不存在、Git空白检查通过、HEAD未变、索引为空。本轮仅做清理和文档更新，未重跑产品测试。
