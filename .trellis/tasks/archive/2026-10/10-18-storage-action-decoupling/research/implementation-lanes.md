# 实施阶段与独占写入交接

用户已批准实施；分支 refactor/storage-action-decoupling，基线 a8acffd。
仓库 /mnt/data/Project/Beamlet。多职责迁移采用串行组件 owner，共享工作区每次仅一个 writer；不并行写同一 checkout，不提交/推送。

| 阶段 | 独占文件/契约 | 隔离 | 门禁与交接 |
| --- | --- | --- | --- |
| Foundation | Storage descriptor/Dataset/Migrations/基础 Repo/连接/Admission/Host；仅基础测试 | 当前 checkout 独占，后续阶段等待 | foundation-handoff.md：确切 profile/descriptor/participant 接口和基础测试 |
| Actions | 新 Actions Storage app、neutral operations/fences/journal、Runtime integration 与所属测试 | Foundation 结束后同 checkout 独占 | actions-handoff.md：API/锁序及 Actions-only 执行证据 |
| Agent | 新 Agent Storage app、Agent 关联/联合事务/领域 reads 与 Agent 接线测试 | Actions 结束后同 checkout 独占 | agent-handoff.md：原子性、恢复/来源/trace 证据 |
| Integration | Node/Server/operator/release manifests/scripts、最终依赖/说明/spec、剩余旧实现清理 | 三组件交接后同 checkout 独占 | implementation-evidence.md：全范围验收与缺项 |
| Check | 独立 trellis-check 全范围审查与修复 | 集成 owner 结束后独占 | independent-review.md：AC1–AC8 结论 |
| Spec sync | backend specs 及任务文档状态，禁止改产品源码/测试/配置 | Check 完成后独占文档写入 | spec-sync.md：源码核对、链接与事实校验 |

组件门禁允许临时旧调用测试尚未迁移，但必须记录，禁止临时默认 profile、旧格式 fallback 或伪造 pass。接口选择需服务已批准 design；实质范围/语义变更向 parent 升级。每个组件写完交接后停止，后续 owner 由 parent 调度。

Foundation 已完成并交接：见 [foundation-handoff.md](foundation-handoff.md)。报告记录 10 项 SQLite 基础契约和 2 项 PostgreSQL 基础契约通过；联合 codec/no-load 聚焦运行 17 passed，后续 SQLite 测试断言增强后的运行 15 passed（未重复执行 PG）。旧 Operator/Server 的 Host 调用尚待集成迁移，warning-fatal compile 暂未通过；不作为全任务验收。当前源码写入权交接给 Actions 阶段。

Actions 已完成并交接：见 [actions-handoff.md](actions-handoff.md)。报告记录 13 项 Actions 契约在真实 SQLite/PostgreSQL 通过，命名 VM Runtime 73 项通过且无排除项；后续 constructor 严格拒绝旧 owner 配置的聚焦 Runtime 20 项通过（1 项分布式排除）。Operation 已无 Agent 编排字段，独立 Runtime 应用闭包无 Agent/Node/Server。旧 Agent 存储和产品接线仍待迁移，当前源码写入权交接给 Agent 阶段。

Agent 已完成并交接：见 [agent-handoff.md](agent-handoff.md)。报告记录全部 109 项 Agent 测试在 SQLite 和真实 PostgreSQL 下分别通过，最终领域存储契约 40 项通过且无排除项。Core 未改动；恢复推进 generation/epoch、显式继续刷新 pending identity、Agent-owned 读取投影已有组件验证。整体仍缺产品集成和独立全范围检查。当前源码写入权交接给 Integration 阶段。

Integration 已完成并交接：见 [implementation-evidence.md](implementation-evidence.md)。报告记录 warning-fatal compile、全伞普通测试 545 passed/37 excluded、真实双适配器、Agent PG109、静态检查及 fresh copied Server/CLI/Web releases 和独立进程 durable e2e 通过。原 named 全伞运行因一个旧 PG view 断言失败，修正后已完成 affected named AgentStorage64 全套复验；原失败保留，不能改称全量 named clean。最终新增用例另有完整所属测试复验。旧领域实现及重复 fixture 已移除；spec 同步待独立检查后执行。当前源码写入权交接给 Check 阶段。

Check 已完成并交接：见 [independent-review.md](independent-review.md)。独立检查修复 Actions 写事务中严格 JSON 加载异常未安全归一化的问题，并补齐两个新应用的 formatter 配置。最终整仓普通测试 552 passed/37 excluded、命名 VM 全套 587 passed/2 E2E phase excluded；Agent PostgreSQL109 通过；编译、扩展格式检查、静态分析、重建后 copied releases 和独立进程 durable e2e 全部通过。AC1–AC8 判定 PASS，READY 进入规范同步与提交审阅。当前仅文档/规范写入待完成，产品源码已通过质量门禁。

Foundation 期间旧领域模块先留待后续 owner 移出；不得因阶段性存在旧模块宣称完成解耦。根 application allowlist/领域 app 创建由各对应阶段处理；集成 owner 最终清理全部旧路径。
