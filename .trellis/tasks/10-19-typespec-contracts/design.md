# 类型契约强化 — 技术设计

## 1. 边界与目标

本任务是一次覆盖整个 umbrella 的契约强化，不是业务重构。用户已确认：公共和私有函数都完善；外部行为、错误原因、持久化格式及进程协议保持不变；发现真实业务缺陷单独报告并等待确认；不新增 GitHub Actions CI。

保持现有 13 个应用边界及依赖方向。类型归实际数据拥有者，不新增跨层的万能 `Beamlet.Types` 应用，不为了引用类型让 Actions/Harness/Foundation 反向依赖 Agent、Runtime 或宿主。

这是一个共同验收的交付目标：领域类型、调用端和私有实现、检查入口必须一致。当前采用单任务、分层增量检查，而不把相互引用的 13 个应用机械拆成独立子任务。每阶段允许局部验证，不允许以完成部分应用替代全项目验收；若实施中出现可独立交付的新范围，应返回规划。

## 2. 现有证据及技术限制

审查基线见 `research/audit-baseline.md`。生产源码约 19,239 行，148 个文件，没有显式 `@spec`。源码行扫描显示私有函数条款众多；这些是 clauses，不是去重后的函数数量，实施第一阶段必须形成 AST 级清单。

特别注意 Elixir typespec 的表达能力：

- 在当前 Elixir 1.20.4 中，字符串字面量不能直接成为 typespec 中的 map key。规划研究通过 `Code.compile_string` 验证 `%{"id" => String.t()}` 会报 `unexpected expression in typespec: "id"`。
- 因此，持久化 JSON、Core 的 string-key state/event 不能伪装成具有精确字符串字面量键的类型。采用有语义名称的 JSON/object/value 类型、已知值域的联合及 `@typedoc` 说明；字段对应关系、精确键集合、字符串枚举、UTF-8、UUID、字节/深度上限继续由既有校验器和测试保证。
- atom-key 的 request、invocation、reply、进程状态及选项可使用必需/可选字段和带标签联合。不要为增强静态表达而改变 wire/storage 的 key 表示。
- `String.t()` 对工具等价于 binary，`@opaque` 也不是运行时封装；不能承诺安全验证或名义身份区分。
- Dialyzer 和覆盖检查互补：前者发现部分实现/契约差异，后者发现声明缺失；二者都不能独立证明领域契约质量。

## 3. 函数覆盖规则

### 3.1 生产函数

以文件 + 模块/模板上下文 + 函数名 + arity + 定义种类为身份，记录位置、可见性、已有 spec、callback 来源及处理结论。

- 自有 `def`、`defp`、`defdelegate`：要求显式 `@spec`，包括自有实现的 OTP/Ecto/Phoenix callbacks；`@impl` 不能代替类型契约。
- 多 clause / guarded definitions：按逻辑函数合并，spec 覆盖全部正常返回分支及支持的输入，而非仅成功分支。
- 默认参数与单独 function head：最大声明 arity 的契约覆盖编译器生成的默认参数包装 arity，不要求为每个生成包装重复手写 spec；显式存在的不同 arity 定义仍分别检查。
- `defmacro` / `defmacrop`、`__using__`、quote 中手写定义：必须识别和分类，使用当前工具链支持的宏契约表达与 `Macro.t()` 等类型，核验编译产物的语义。不能把 quote 里的 def 误记为宿主函数，也不能一律忽略模板里的自有代码。
- 不能静态归属的动态生成定义：输出明确的位置与原因，必须有精确审计条目。保留编译/类型检查作为第二证据，不能执行任意宏来完成源码扫描。
- 框架宏自动生成定义不要求逐个补源码 spec，但需要区分生成来源。框架重写的 Phoenix component、嵌套模块、custom Repo quote 要有专门 fixture。

任何必要特殊项必须绑定精确身份/位置及原因，检查应识别过期、重复或扩大范围的例外。禁止整应用/整模块跳过。普通私有函数不在例外范围。

### 3.2 公共和私有类型精度

- 公共共享数据：在拥有者声明 `@type`，用 `@typedoc` 说明含义、边界与运行时约束；调用端引用远程类型。
- 模块内部状态、累加器、解析结果：使用局部类型；只供内部使用的类型优先 `@typep`。
- 真正表示独立、外部不应依赖内部形状的值才考虑 `@opaque`；先检查合法字段访问。当前 Ref/handle 不能因文档出现 opaque 字样就机械改成 opaque。
- 有真实输入/输出相关性的工具函数使用参数化类型或 `when value: var`，而非把结果全部擦成 term。
- 有意开放 payload、handler-specific reason、解析失败输入允许 term，但要能说明开放原因。验证器必须保留其实际接受的坏输入类型，不能通过 spec 把已测试的错误分支声明为不可用。
- 对完整构造态、初始化/未 admission 的中间态和有效终态分别命名或用联合准确表达，不将所有字段都收窄到最终状态。
- `no_return()` 仅用于永远不正常返回的函数；正常函数可能 raise 不需要加 `| no_return()`。

## 4. 类型归属与实施方向

| 层 | 类型拥有者与检查重点 |
| --- | --- |
| Actions | Operation、Result、Execution、live refs、Handler context；修正 credentials/claims 可空 map；保留通用 payload/reason 的开放性 |
| Harness | Context、Model/Tool、catalogue/schema/JSON 边界及 provider-specific 参数；typed atom-key request/invocation/reply、tagged tool calls；不新增 sibling dependency |
| Foundation Storage | Repo 身份、installation descriptor/component/migration、事务函数泛型、JSON/artifact/reference；只拥有基础中立数据，不引用域模块 |
| Actions Storage | Operation/attempt/journal/evidence/dispatch scope 输入、schema 与固定错误；依赖 Actions/Foundation 的既有方向 |
| Agent Storage | Agent/event/command/checkpoint/inheritance/history 输入及返回；不依赖 Agent/Core 来引用类型；保留自己的 schema/projection 所有权 |
| Runtime | submit/control options、prepared identity、Persistence、coordinator/gateway/directory 状态与消息；复用下层 Operation/Result/storage 类型 |
| Agent Core | 纯 reducer/control/event/context/decision 类型；string-key 限制明确记录，不新增对 Storage/Runtime 的依赖 |
| Agent | Ref、ModelBinding、durable locator、loader/history/trace、资源/生命周期/委派与 Server 私有状态；严格保留不确定结果和恢复语义 |
| Node / Server | trusted profile、role/cluster/discovery/observation 与 startup/config results；不产生对宿主的反向引用 |
| I18n / CLI / Web | locale、command/session/rendering、Host/preset/handle/LiveView state 和 callback；复用既有 Plug/Phoenix/Owl 类型，不把动态 assigns 冒充封闭结构 |

Foundation/Actions/Harness 先行；Actions Storage 在 Foundation/Actions 后；Agent Storage 在其后；Runtime/Core 再到 Agent/Node/hosts。实际依赖图以各 `mix.exs` 为准，类型引用不能制造新编译循环。

## 5. 可执行的契约覆盖门禁

新增独立开发脚本，拟定入口 `elixir scripts/quality/check-contracts.exs`，不放入某个生产应用，不新增运行时依赖。

- 使用 `Code.string_to_quoted` 的 AST 分析，不采用 grep 统计；只解析、不启动应用、不执行输入源码。
- 默认检查 `apps/*/lib/**/*.ex`。开发工具自身也应有准确契约；fixture/test DSL 不当作生产模块扫描。
- 输出总覆盖、公共/私有/委托/宏/模板分项、缺失的 file:line/module/name/arity、精确特殊项。任何解析失败或未知需审计的定义不能伪装为已覆盖。
- 缺失或无效/过期特殊项返回非零；全范围无缺失才通过。
- 提供独立 ExUnit fixtures/测试，拟定 `elixir scripts/quality/check-contracts-test.exs`：缺失 private、公有函数、默认参数、function head、多 clause/guards、nested module、delegate、overloaded spec、macro/quote、自有 callback、组件改写、解析失败、过期例外等。
- 增加变异/负向验证：移除已有 public/private spec 或新增未标注函数时，必须失败。覆盖率检查只证明声明存在，不能替代人工语义审查或 Dialyzer。

门禁接入现有 `.pre-commit-config.yaml` 和 `scripts/deployment/check-local.sh`，包含对门禁脚本自身变化的触发，不新增 `.github/workflows`。不增加自动修复/自动补 term 的功能。

## 6. Dialyzer 告警策略

- 保留当前默认检查及 unknown 检查；目标是在根项目配置中开启 `:unmatched_returns`，使现有 `mix dialyzer` 入口一致执行，而非本地额外命令才生效。
- 对基线 68 条逐项记录位置/类别、实际返回、处置和理由。代码移动后的告警不能按旧行号硬匹配。
- 必须处理的失败不能为了保持类型检查通过而吞掉；一旦判断为真实行为缺陷，记录并等待用户另行授权，相关门禁不虚报通过。
- 有意副作用/best-effort 结果可以显式丢弃，但必须经语义核对；在不显然的位置写明原因。不得把 `_ =` 当批量清零方式，也不允许新增全局/模块告警屏蔽或目录排除。
- 待有足够 spec 后可执行 `underspecs` 等探索检查并记录信息；不把 overspecs/specdiffs 等全部设为强制门禁。对于有意较宽 API，需要保持支持范围而非迁就推断。
- 不引入 ignore 文件或不必要的依赖；若工具/上游真实缺陷阻塞，给出最小复现并回到规划讨论，不静默降级。

## 7. 兼容性、验证及回退

主要变更是 annotations、文档、开发工具和配置，运行时表示不变。不迁移 schema，不改状态机、超时/取消/幂等、错误标签、协议、catalogue 文案或 provider 行为，不通过改变测试断言获得通过。

每层编译、Dialyzer 和回归后再推进；检查公开导出和应用依赖没有意外改变。最终按 implement.md 执行全范围检查，保留分项覆盖报告、告警处置表、行为缺陷清单和准确测试证据。现有 PLT 检查与 fresh project PLT 验证分开记录；不声称本任务验证了物理跨机或重建了所有 Erlang 核心 PLT。

回退按层撤回本任务的 annotations 和工具配置，不回滚用户其他改动；开发门禁最后接线，避免中间覆盖不全阻塞正常提交。若必须改变运行时语义或应用依赖方向，立即停止该部分并重新审批。
