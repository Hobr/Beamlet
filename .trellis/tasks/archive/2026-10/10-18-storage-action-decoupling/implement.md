# 执行计划：Storage / Actions / Agent 解耦

## 前置与边界

用户已审阅并于 2026-10-18 明确批准本执行计划与设计进入实施，也已批准允许格式/API 调整。任务激活后按下列顺序推进。本文件阶段为同一集成迁移的检查点，不代表可单独发布。

基线 a8acffd；实施前复核 git status、用户新增修改和当前任务。只修改本任务相关代码/说明；不处理无关格式或生成资源。

## 1. 基础层与新应用

- [x] 加载 trellis-before-dev 及本任务 manifests；按当前阶段调度 implement/check。
- [x] 创建 beamlet_actions_storage / beamlet_agent_storage（无 Application callback），声明直接依赖，更新 backend_apps 和相关 app manifests。
- [x] 将领域 schemas/migrations/events/codecs/record helpers 分到归属库；Storage 仅保留实际共享基础能力。
- [x] 设计并实现 format3 descriptor、profile/component/migration 校验；迁移模块归所属应用，不允许基础层动态探测 Agent。
- [x] 新建三个明确 profile，冻结唯一有序 migration IDs 与元数据契约。
- [x] 保持 SQLite/PG 配置、路径隔离、rollback/error 分类；通用 artifact 和 canonical JSON 摘要稳定。
- [x] 将原 Storage 契约按基础、Actions、Agent 归属迁移；共享 adapter fixture 不反向使基础层依赖领域层。

检查点：基础库与新 app 可编译，基础数据集/readonly preflight/format 拒绝测试通过。避免留下“暂时允许缺少组件”的过渡行为。

## 2. Actions 持久化与 Runtime

- [x] 实现无 Agent 字段和外键的 Operation/attempt/evidence/Operation events；executor journal 与 terminal artifacts 归 Actions Storage。
- [x] 实现中立 scope/epoch 的创建、轮换、事务内绑定及 claim 校验，冻结锁序和错误映射。
- [x] 实现单事务 participant，不自行提交；保留唯一性、CAS、相同 acceptance 重放、冲突拒绝和 late evidence 行为。
- [x] Runtime 改用 Actions Storage，删除 Agent-shaped Persistence.owner 与 Agent 表访问；保留 PID owner 生命周期及其现有监控清理保证。
- [x] 已准备 submit 核对完整 Operation/attempt/description/executor boot/version/state 及可选 scope 绑定，防止错换 prepared identity。
- [x] 通过非 model/tool 的独立 Handler，验证仅 Actions 表的新数据集完整执行、重启查询；检查源码和实际表清单均无 Agent。

检查点：AC1/AC2、Actions CAS/证据/日志重启行为通过；独立 Actions 测试不得依赖 Agent fixture。

## 3. Agent 联合事务与读取

- [x] 实现 Agent Storage schema、agent_operations、commands/Agent events/checkpoints/source/inheritance。
- [x] Agent create 同事务创建 scope，restore 同事务推进 generation/epoch；Agent->scope->Operation 锁序一致。
- [x] prepare_operations 调用 Actions participant 并写不可变关联/Agent events/command response；批成员任一失败全回滚。
- [x] consume/fork/restore/checkpoint 保留 generation、来源授权、accepted digest 与 artifact 验证；跨域规则留在 Agent Storage。
- [x] Loader/History/TraceSnapshot/TraceVerifier/Export 改读 Agent 投影与 Actions 接口；必要 envelope 变化显式版本化，Core 的输入契约尽量维持且不得新增 IO 依赖。
- [x] 删除旧 Beamlet.Storage 领域入口，迁移全部调用，不留 shim 或双写。

检查点：AC3–AC5；真实事务同步测试覆盖两个 restore/claim 顺序与 accept/claim 竞争，独立检查锁序。不得把分步提交、外部回调或先检查后写当作原子性替代。

## 4. Host / operator / release

- [x] Storage.Host/Admission 仅管理显式描述的通用数据集；Node.Storage 组合具体 authority/journal profiles 与 Runtime/Agent 接线。
- [x] operator 与保留命令名的 Mix task 移至 Node 组合层；Server 改调用新入口，库加载不启 Repo、boot 不迁移。
- [x] 更新测试、根 app allowlist、部署脚本和 copied artifact 检查，确认 Actions-only 库闭包无 Agent/Node/host。
- [x] 新库显式初始化；构建旧 authority2/journal1 测试夹具并验证拒绝后 schema/业务内容未变，覆盖 component/identity/profile/backup/migration mismatch。
- [x] 更新 READMEs、docs/architecture/agent-operation-persistence.md 及相关 backend specs 为实际完成的职责与协议；说明 API/格式断点及 operator 新入口。

检查点：AC6/AC7，Node/Server 接线与安全拒绝、admission、无持久化行为回归通过。

## 5. 验证命令与证据

所有命令从仓库根运行。先核对 Nix/Elixir/OTP、依赖与本地 PostgreSQL 前提；需要时使用 `nix develop`。新 app 路径在创建后才存在。

聚焦检查：

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test apps/beamlet_storage/test apps/beamlet_actions_storage/test apps/beamlet_agent_storage/test --seed 631927
mix test apps/beamlet_runtime/test/beamlet/durable_runtime_test.exs apps/beamlet_runtime/test/beamlet/durable_admission_test.exs apps/beamlet_agent/test apps/beamlet_node/test apps/beamlet_app_server/test --seed 631927
```

双适配器共用同一断言集，PostgreSQL 使用隔离临时 cluster 和 fixture 的 `BEAMLET_PG_SOCKET_DIR`/`BEAMLET_PG_PORT`/`BEAMLET_PG_USER`，只创建/删除本次临时库。报告 SQLite 与 PG 的各自 executed/excluded 数量；journal 保持现有 SQLite 后端，不新增 PG journal 需求。

全范围检查：

```bash
mix test --seed 631927
mix credo --strict --all
mix dialyzer
mix sobelow
mix gettext.extract --check-up-to-date
bash scripts/deployment/durable-e2e.sh
```

使用独立短名和 cookie 的命名 VM 运行 `mix test --include distributed --seed 631927`，依据 test helpers/现有 release spec 的排除项记录实际用例数，避免误称已运行默认排除的测试。保留 peer 的低 scheduler 配置，明确只证明同物理机多 VM。

发布闭包按 `.trellis/spec/backend/backend-release.md` 和 `scripts/deployment/README.md` 现有步骤重建 Server/CLI/Web（server/CLI 使用 `BEAMLET_BACKEND_BUILD=1`），再运行：

```bash
bash scripts/deployment/check-release.sh
```

检查包括 copied artifact、命名 start/RPC/stop、各产品入口和缺失旧库安全状态，不只 eval。不对真实业务库运行初始化。

新代码路径使用主动 LSP diagnostics（无结果/超时为不确定），Elixir 编译、测试及 Dialyzer 为主要运行证据。不为了通过检查扩大超时、弱化断言或忽略 Credo 规则。只在新改动、失败或未决风险需要时复跑。

## 6. 独立检查与完成

- [x] 独立 check 对照 AC1–AC8 审查所有阶段累计 diff，重点排查基础层反向依赖、隐藏 Agent schema/词汇、参与事务早提交、锁序、伪造/错配 prepared identity、旧格式写入和缺失 PG 覆盖。
- [x] 在 research/implementation-evidence.md 逐项记录命令、环境、实际结果、失败及解决，不把当前规划当作通过证据。
- [x] 按 trellis-update-spec 更新已实现契约（Phase 3.3）；文档链接、源码签名、旧 API 与 whitespace 核验通过，见 research/spec-sync.md。
- [x] 适用检查通过，用户确认拆分方案后完成 7 个工作提交；finish-work 已归档任务，journal 由后续收尾步骤记录。

## 风险与回退点

- 数据模型分离、scope 锁和 trace 投影是重点人工检查区域；schema/API 迁移必须与调用方同步，不能发布半迁移状态。
- 回退代码阶段只恢复本任务明确修改的文件/提交，不覆盖用户新修改，不使用破坏性整库重置。
- 测试失败保留独立日志与临时数据用于诊断；仅清理自己创建的测试资源。
- 真实环境使用新数据集路径。回退旧代码时选原旧库；新格式无降级/旧数据自动导入机制。
- SQLite/PG 或 release 前提不可用时标记 blocked/inconclusive，不能宣告 AC8 完成。
