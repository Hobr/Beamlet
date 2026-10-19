# 中文阶段实施分工

本任务跨多个独立应用边界，采用多个组件所有者顺序实施，同一时刻只有一个写入者。所有组件使用 `/mnt/data/Project/Beamlet` 的 `dev` 工作区，隔离方式为串行独占，禁止并发写入。父会话在组件运行期间不修改产品文件。所有组件均仅能修改自己的文档/注释，不能提交、改行为、更新依赖或启动英文阶段。

| 组件 | 独占文件范围 | 下一检查点 | 持久交接 | 独立依据 |
| --- | --- | --- | --- | --- |
| contracts | apps/beamlet_actions、apps/beamlet_harness、apps/beamlet_agent_core | 读取全部16个源文件、中文说明/README、格式与差异 | research/coverage-contracts.md | 独立契约和纯核心边界 |
| foundation | apps/beamlet_storage | 读取全部15个源文件、中文说明/README | research/coverage-foundation.md | 通用资源与安装事务 |
| domain-storage | apps/beamlet_actions_storage、apps/beamlet_agent_storage | 读取全部36个源文件、中文说明/README | research/coverage-domain-storage.md | 领域持久化所有权 |
| orchestration | apps/beamlet_runtime、apps/beamlet_agent、apps/beamlet_node | 读取全部41个源文件、中文说明/README | research/coverage-orchestration.md | 执行与进程生命周期 |
| hosts | apps/beamlet_cli、apps/beamlet_app_server、apps/beamlet_app_web、apps/beamlet_i18n | 读取全部40个源文件、中文README及Web专题 | research/coverage-hosts.md | 宿主、展示与语言所有权 |
| root-docs | 根README/术语/架构、docs/architecture维护说明、scripts、config、根及应用mix说明注释 | 中文文档、链接、命令准确性 | research/coverage-root-docs.md | 项目导航与运维入口 |
| integration | 共同coverage.md、中文verification.md及上述文档/注释的小范围集成修正 | 完整性、编译、AST与质量检查 | verification.md | 仅在六个组件交接完成后集成 |

root-docs 组件不得重写前面组件拥有的应用README或lib文件；各应用mix文件仅补说明性注释。集成所有者只补缺口和修正问题，不另做组件实现。任何任务失败、未完成或运行基础设施错误都停止顺序执行，交父会话处理；不能以进程正常退出替代真实完成。

英文阶段不得在此工作流启动。中文检查与基线由父会话验收后，按已获批准的顺序另行继续。
