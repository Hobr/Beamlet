# 类型契约强化 — 执行与验收计划

按用户交付前的明确要求，已删除重复阶段报告、原始/压缩日志及临时探针，精简生成清单，并在 `research/final-verification.md` 保留执行结果、历史失败和限制。此清理要求优先于下文原计划的全量原始日志保留约定；正式检查器及其40项回归测试保留。

## 前置门禁

- [x] 用户在最终方案摘要之后明确批准实施；已批准并进入 in_progress。
- [x] `prd.md`、`design.md`、本文件及两个 jsonl 清单齐全，`task.py validate` 通过。
- [x] 记录当前 HEAD/工作区；重新加载相关 backend 规范，不能把之前审查的干净状态当实施前事实。
- [x] 只有完成上述审核后执行 `task.py start`。按项目 Phase 2 路由实施/检查；任何委派 prompt 第一行必须为 `Active task: .trellis/tasks/10-19-typespec-contracts`。本规划阶段不派实施代理。

## 阶段 A — 可审计基线与检查器（R1、R5 / AC1、AC5）

- [x] AST 建立完整函数清单，分列公有/私有、arity、clauses、默认参数、delegate、宏/quote、callback 与生成项；保存 `research/function-inventory.md`，不再用 clauses 数量代替函数数量。
- [x] 记录 13 应用的当前依赖，明确类型拥有者；核对规范中的边界与当前 mix.exs。
- [x] 以独立脚本实现 `scripts/quality/check-contracts.exs`，并配 `scripts/quality/check-contracts-test.exs`，不增加生产依赖或根 umbrella app。
- [x] fixtures 覆盖公有/私有缺失、同名多 arity、多 clauses/guards、default wrappers、function head、nested module、delegates、overloaded specs、macro/quote 模板、自有 callback、Phoenix component/框架生成边界、解析错误、过期特殊项。
- [x] 负向 fixture 删除 private/public spec 或新增缺失函数均必须非零；不能只测通过用例。
- [x] 完整生产覆盖此时预期失败；保留失败证据，不提前接入强制 hook，不自动生成宽泛 spec。

检查点：检查器测试通过，清单完整且未知模板需审计，不声称当前生产覆盖已完成。

## 阶段 B — 底层领域与独立能力（R1–R4 / AC1–AC3）

- [x] Actions：完善 structs/types、构造/校验/私有帮助函数及 Handler context；修正 claims/credentials optional map，保留任意 payload 的开放语义与未 admission 的合法中间态。
- [x] Harness：完善 Context、JSON/catalogue/schema、Model/Tool callback、provider、WorkspaceRead 的公私有函数。精准表达 atom-key request/invocation/reply 和 tagged calls，文档说明 wire JSON 的静态限制。
- [x] Foundation Storage：完善 Repo/Installation/Dataset/codec/JSON/artifact/reference/transaction/types；自有 quote 模板定义纳入审查。泛型函数应保留输入输出关系，不将任意事务结果伪装成单一业务类型。
- [x] 对每个函数读取全部 clauses、调用方与相邻测试后写 spec。必要的类型辅助声明留在实际拥有者，不引入反向依赖。

每个应用完成后：格式、warning-fatal 编译、对应测试、当前 Dialyzer 和覆盖分项核对。保留 Operation 空 map 和代表性非法输入的验证证据。

## 阶段 C — 存储域与纯 Core（R1–R4 / AC1–AC3）

- [x] Actions Storage：Operation/attempt/event/journal/evidence/dispatch scope、changeset/schema、read/write facades及全部私有函数。
- [x] Agent Storage：Agent/command/event/checkpoint/inheritance/history/projection、changeset/schema/read/write facades及全部私有函数；不引用 Agent/Core 类型以免倒置依赖。
- [x] Agent Core：reducer/control/events/context/decisions、递归/累加器/中间状态；string-key JSON 类型结合语义文档与既有 validator/tests，不写非法字符串字面量键 typespec。
- [x] 明确通用 Ecto 原始返回与 facade 安全错误的区别，保持异常窄分类、事务回滚和 outcome-unknown 原语义。

检查点：对应 SQLite 套件通过；在环境可用时执行现有 PG owning suites，记录实际运行与跳过，缺失不能当通过；编译及 Dialyzer 验证跨域类型引用。

## 阶段 D — Runtime、Agent、Node 与宿主（R1–R4 / AC1–AC3）

- [x] Runtime：facade options/prepared/Persistence、Directory/Gateway/Coordinator 状态、消息、生命周期、控制及私有帮助函数；保留 cancel/deadline/uncertain 区分。
- [x] Agent：Ref/ModelBinding/Server、资源/委派/owner、durable loader/history/export/verifier、纯集成帮助函数及全部私有定义；保留合法 live field access，不强行 opaque。
- [x] Node / App Server：profiles/roles/host/storage composition、cluster/discovery/observation、启动结果和私有验证器。
- [x] I18n / CLI / Web：locale/catalogue、commands/session/renderer/runner、Host/presets/handles、controllers/components/LiveView callbacks、Web __using__ 模板和私有帮助函数。
- [x] 核对所有公开导出无意外变化，type-only 依赖不产生跨应用反向引用，callback/自定义模板不遗漏。

检查点：全生产覆盖无未解释缺失，代表性原有坏输入路径仍被声明并测试；既有集成回归保持不变。

## 阶段 E — 返回值处置与门禁接线（R4、R5 / AC4、AC5、AC7）

- [x] 重新执行 `mix dialyzer --unmatched_returns --format short`，形成 `research/return-dispositions.md`。将基线 68 条逐项映射到实际函数、返回语义和处置；新增告警同样审查。
- [x] migration/query!、Gettext 提取、有意 best-effort 等经核实后可显式丢弃成功/不关心结果；非显然处写理由。不能批量 `_ =` 或 blanket ignore。
- [x] 若发现必须改变行为才可修复的缺陷，记录至 `research/behavior-findings.md`，先请用户单独确认，不擅自改行为或把该项宣称已解决。
- [x] 根 Dialyzer 配置启用 `:unmatched_returns`，保留默认/unknown 检查；不新增全局屏蔽、ignore file、应用排除或 ignore-exit-status。
- [x] 新 coverage gate 接入 `.pre-commit-config.yaml` 和 `scripts/deployment/check-local.sh`，对源码、检查器与精确特殊项配置变化都触发；无新增 CI。
- [x] 在 README/质量规范记录实际入口；更新类型规范，包括 public/private、callback、动态输入、JSON 字符串 key、opaque、泛型、异常与丢弃返回值的约定，并在 backend 索引链接。

## 阶段 F — 最终全范围验收（AC1–AC7）

从 umbrella 根执行，不能依赖子目录 Mix 命令。每次最终候选验收使用不同证据目录，保留失败和最终结果，不覆盖原始失败日志。

### 必须执行

```bash
elixir scripts/quality/check-contracts-test.exs
elixir scripts/quality/check-contracts.exs
mix format --check-formatted
mix compile --warnings-as-errors
mix test --seed 631927
mix credo
mix credo --strict --all
mix dialyzer
mix gettext.extract --check-up-to-date
mix sobelow
mix xref graph --format cycles
git diff --check
```

- [x] 覆盖门禁输出全部 13 应用的公共/私有覆盖与精确特殊项，没有静默忽略。
- [x] 默认 `mix dialyzer` 已包含选定的 unmatched_returns，0 errors/0 skipped；检查过 PLT 的结果与完全新 project PLT 分开记录。
- [x] 验证实际门禁 wiring：pre-commit 的文件触发与 pass_filenames，集成脚本失败传播，不能仅验证脚本可手动运行。
- [x] 针对 bad map/request/reply、构造/中间态、callback 实现、泛型帮助函数与 quote 生成函数核对编译契约；如使用隔离负向类型 probe，其来源/预期/实际告警必须保留，不混入生产 app。
- [x] 源码 diff 审查确认没有 API、错误原子、消息、schema、超时、安全校验、文案或断言语义变化；若有发现，回退该改动或重新审批。

### 既有集成与隔离验证

- [x] 按当前 tests 配置，使用隔离节点名/cookie和低调度器数执行实际 named distributed tests，保留 executed/skipped 计数；不声称物理跨机已验证。
- [x] 执行既有 durable 两进程验证 `bash scripts/deployment/durable-e2e.sh`；PG 等前置条件不可用时明确报告阻塞/未执行，不能标全通过。
- [x] 在任务拥有的新 `_build` 子目录，通过标准 `MIX_BUILD_PATH` 隔离构建执行一次 `mix dialyzer`，记录 project PLT 新建/分析和使用的核心缓存；不要删除已有 PLT 或声称核心缓存也被从零重建。
- [x] 活动 LSP 对变更 `.ex` 路径作主动诊断（分批）；无服务/超时仅记为 inconclusive，不能取代 Mix 检查或当作 clean。
- [x] `research/final-verification.md` 按 AC1–AC7 映射覆盖统计、命令、日志、语义审查、特殊项及环境限制；原测试数量不应仅凭旧任务推断。

## 阶段 G — 交付

- [x] 运行最终范围质量检查与规范一致性审查，确认 PRD 没有尚未履行的范围。
- [x] 完成 spec 更新并核对文档链接和命令；真实行为缺陷若未授权保留为单独发现，不混成已完成。
- [x] 按 Trellis 提交流程交付：按应用/职责拆为18个工作提交；不执行 push/发布。任务随后按 finish-work 指引归档并记录会话。

## 回退点

每个分层阶段结束为回退检查点，优先保留语义不变的类型声明；返工时只撤本任务改动。门禁最后接入，避免未完成覆盖阻塞正常流程。若必须扩大到行为修改、新依赖方向或 CI，停止相关部分、更新规划并重新确认，不在实现时默默扩大范围。
