# 持久数据契约与存储基础执行计划

状态：in_progress。用户于 2026-10-18 批准 A 阶段实施，包括添加已评审依赖与准备隔离数据库测试设施；B–F 未获开工授权。当前分支 feat/durable-storage。

## 开工门

- [x] 用户于 2026-10-18 批准本子任务；无上游实现依赖，仅 A 开工。
- [x] 重新核对主设计、父设计、根/应用 manifests、Node 启动与当前协议大小；将接口职责、起始限额及候选版本写入 design.md。
- [x] 只读核对官方 release 元数据和固定版 SQLite 选项，记录于 research/planning-evidence.md；尚无实际依赖/数据库兼容证据。
- [x] 已准备隔离 PostgreSQL 集群（nix postgresql 18.6，Unix socket、端口 5439、`--auth=trust`、`listen_addresses=''`）及 SQLite 真实文件目录；记录实际连接与版本于 research/integration-evidence.md，集群随后停止。
- [x] implement/check manifests 各 11 条通过校验；已按本会话上下文激活 A（in_progress），其他任务保持 planning。

## 实施顺序

- [x] beamlet_storage 已声明精确版本（ecto 3.14.0、ecto_sql 3.14.0、ecto_sqlite3 0.25.0、postgrex 0.22.4、jason 1.4.5）并同步根 backend_apps；无 override，OTP 29 / Elixir 1.20 普通与 BEAMLET_BACKEND_BUILD=1 编译均 exit 0。
- [x] 无 Application 回调的 Repo 选择、显式 initialize/open 与 authority/journal 分离迁移已实现；未接入 Node/宿主配置。
- [x] 严格 codec/稳定 digest、schema/changeset、artifact、terminal 附件与三个记录事务门面已实现且不产生外部副作用。
- [x] 共同契约测试已实现并在真实 SQLite 文件与真实 PostgreSQL 上运行（9 + 10 用例全通过）；SQLite 竞争另由独立 Repo/连接用例覆盖。
- [x] 两库契约覆盖 command/receipt 幂等与 digest 冲突、CAS 竞争、同事务回滚、提交结果未知、限额/分页边界，以及关闭重开、较新格式与备份标记拒绝（共享套件 3 × 2 个场景）；已修正集成阶段的 `stop_repo/1` 自递归测试 bug，不再存在挂起。
- [x] 实际引擎 3.53.4，WAL/FULL/FK 逐连接核对，`busy_timeout` PRAGMA 为 0 属 Exqlite NIF 处理器设计（不得用 PRAGMA 覆盖）；写事务 immediate、只读保持 deferred；PostgreSQL 每连接核对 synchronous_commit/fsync。
- [x] 已更新 database-guidelines/directory-structure/index 的现状章节、beamlet_storage README 及 research/integration-evidence.md；未声称业务恢复。

## 未来验证命令与证据

下列是新增应用后才可执行的验证，不是本轮已运行命令：

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test apps/beamlet_storage/test
BEAMLET_BACKEND_BUILD=1 mix compile --warnings-as-errors
BEAMLET_BACKEND_BUILD=1 mix test apps/beamlet_storage/test
mix test
mix credo --strict
mix dialyzer
mix sobelow
```

Storage 契约套件须明确报告 SQLite 与 PostgreSQL 各自实际用例数，不把无连接的 skip 当通过。测试 adapter/连接参数的具体注入方式在测试设施中锁定，不虚构当前已有的命令或 CI。对受影响的现有 named distributed 和 release 检查按后端质量指南补充，须先核对真实入口及环境。

## 验证与收尾

- [x] 全部：两库契约（含关闭重开/格式拒绝/备份标记）、日志事务、加载无副作用、限额与错误分类均有父会话实跑证据（见 [research/a-verification.md](./research/a-verification.md)）。
- [x] format、普通/后端 warning-fatal compile、针对性/完整 ExUnit、`mix credo`(exit 0)、`mix dialyzer`(0 errors)、`mix sobelow`(exit 0，一条常量 SQL 的低置信提示) 均已实跑；`mix credo --strict` exit 14 作为 advisory 记录；named distributed/release 入口与本阶段无关，未将未跑项当通过。
- [x] spec 现状章节、README、证据与交接已更新；下游规划仍标为 proposal。
- [x] 范围核对：未改 Agent/Runtime/Node、未新增宿主配置、未实现 B–F；无回退动作。
