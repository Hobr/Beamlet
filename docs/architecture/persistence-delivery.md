# Durable 重构交付与验收计划

状态：配套[持久化设计](./agent-operation-persistence.md)的重构已由 durable-rebuild 及四个子任务实施并独立验收。以下 A–E 是验收维度，实际实施按 Storage→Runtime→Agent→引用与产品交付执行。旧 Stage A–F 成绩不作为本次证据。

## 1. 范围

直接以新设计替换旧消息检查点模型，不要求旧 API、数据库或检查点兼容。实施任务仍须显式定义数据集初始化/格式拒绝与开发数据处理，不能启动时自动丢弃旧库。authority 使用新格式 2，journal 保持格式 1；旧 authority 迁移与兼容入口已删除，已有数据不自动迁移或删除。

沿用 Ecto、权威 SQLite/PostgreSQL、executor 本地 SQLite、单 attempt、未知不自动重发、暂停恢复、显式继续。Agent 输入和编排归 Agent，确定 LLM/Tool 输入归 Operation，业务输出归 accepted Result，执行观察归 executor evidence。

## 2. 已交付范围与验收维度

### A. 事件与内容归属

- 用户原始输入、决定、配置变化具有独立记录；模型/工具正文仅由 Operation/Result 或其不可变 artifact 拥有。
- 全部模型 Operation 关联 agent/turn/step；来源清单由 Operation 拥有，Agent 只保存编排引用。
- 定义连续已提交事件 seq、类型/版本、因果引用和幂等身份，移除 Agent 结果事件预留槽位。
- 保留权威 current-state CAS 与唯一约束，事件归约只用于 Agent，不要求 Runtime 全面事件溯源。

验收：不读取旧 messages/assistant 检查点即可找到原始输入与所有实际请求/回复；Agent 事件/检查点中无 LLM/Tool 正文副本；accepted Result 内容不依赖 executor 在线；双库真实事务失败无部分引用或事实。

### B. Agent 纯 reducer 与检查点

- 控制状态由受支持的已提交事件归约，检查点绑定 through_seq 和 reducer/state 版本，只加速重建。
- 活跃 Agent 仅在提交后推进投影；缺通知时可读取事实，不根据临时展示恢复。
- 有界分页加载不可变引用，未知事件/坏引用明确阻塞；事件归约不执行 I/O、模型或 Tool。

验收：完整重放、任意合法检查点加后缀重放、活跃已提交状态三者一致；删除/损坏缓存检查点可重建，坏历史不能静默跳过；对重放期间所有外部调用设置计数并断言为零；旧 generation 写拒绝。

### C. 上下文构建与原子准备

- 先实现普通对话策略，随后策略可选窗口、检索、摘要；不在本阶段实现全部策略。
- 固定来源范围、顺序、policy/指令版本与变换说明，构建临时 messages/catalogue。
- 将确定逻辑请求作为 LLM Operation 输入；原子提交 Operation/attempt、Agent 准备事件和等待位置，提交后派发。
- 模型和 Tool 使用同一事实归属；结果消费仅追加引用与控制转换，不保存 Tool message 正文。

验收：相同来源与版本构建相同逻辑请求；策略/工具 schema 更新不改变已准备请求；未知证据不被策略采纳为成功；两个 Tool 反序完成仍按原 ordinal 消费；消费前/后崩溃不重复执行或消费。摘要若调用模型，同样走 Operation。

### D. Runtime 证据与恢复边界

- 复用 prepared/send_claimed、start_intent、receipt、accepted Result 与本地/远端统一准入协议。
- Agent 不接触节点发现、Gateway PID、boot 路由，Runtime 不解释对话策略。
- 恢复归约后 paused；只读 inspect 不修改历史；激活以稳定身份幂等记录中断、增加 generation 并退役旧发送者。
- 查询已有证据不 admit；未知效果阻塞，显式决定新工作使用新 Operation。

验收：在准备提交、claim、send、start_intent、外部改变、receipt、accept、consume 前后逐点终止业务进程或 VM；调用总数不因恢复增加；已采纳结果不可覆盖；cancel/deadline/断连不伪造远端停止；执行器全部离线仍能查看和重建 Agent。覆盖本地/分布式 × 内存/durable，禁止 durable 静默降级。

### E. Fork、导出与图投影

- 同权威安全 fork 创建新 Agent，物化继承引用清单，保留直接可读的不可变内容闭包，不复制 Operation 为新执行。
- 新 Agent 生命周期独立，无父事件前缀递归；内容引用仍需保留，不承诺可删除源内容。
- 固定导出高水位及引用闭包；图由因果/来源/采纳/消费/汇合边派生，无另一份权威状态。

验收：新 Agent paused/await_input；不继承 pending/消费/命令去重/provider session；继承内容不计新执行或新费用；源迟到结果不推进新 Agent；共享环境风险未确认默认禁执行；导出包含所有所需内容与摘要，缺失/脱敏明确标记；图保留并发偏序与 unknown，不假造全局完成顺序。

## 3. 必须保留的存储约束

真实 SQLite 文件与真实 PostgreSQL 运行共享契约；未运行的 adapter 不得报告通过。迁移显式、身份/角色/新格式/备份标记拒绝；SQLite FULL/WAL/FK/immediate 写入及真实 busy 竞争，PostgreSQL 同步提交与 CAS。事务内无外部副作用；提交结果未知先按稳定身份重读，不自动重试写事务或 Handler。

authority 与 executor journal 分开，单机也不绕过。已采纳结果内容在权威侧独立可读；ACK 不是停止证明，start_intent/not_found 不是未执行证明。保留首个停止触发原因与真实终止结果。Node/Repo 注册 ready 不授权 durable 工作，存储失败关闭相关准入。

所有 wire envelope、事件/事务/请求/结果/artifact 字节、恢复页数与内存、构建预算、队列、查询时间、导出并发有明确上限。长历史有界处理，不能为恢复速度丢事实或任意扩大 wire cap。首版不自动 GC；未来清理必须覆盖引用、fork 和导出闭包。

## 4. 需求追踪

| 验收目标 | 设计位置 | 验证内容 |
| --- | --- | --- |
| 单一正文归属 | 主设计 2、4、5 | Agent 无副本，输入独立存在，引用可校验 |
| 事件恢复而非副作用重跑 | 4.1、4.3、7 | 重放等价与零外部调用 |
| 确定请求与自由上下文 | 4.2、6.1 | 来源与策略切换，已准备请求不变 |
| 分布式职责正交 | 3、6.2 | 部署组合测试，无 Agent 路由依赖 |
| 副作用屏障和未知语义 | 6、7、10 | 双库故障注入、调用计数、单次采纳/消费 |
| 安全 fork 与图/导出 | 8 | 引用保留、风险 gate、偏序和完整闭包 |

## 5. 最终验收结果

新候选在 Agent SQLite、Agent PostgreSQL 两种配置下分别通过 503 项全伞测试（各排除 35 项单独执行的 distributed 和 2 项 e2e）；Storage 74 项始终包含真实 SQLite/PostgreSQL。Agent 共 104 项，引用式 fork/历史/导出专项 39 项。35 项实际 named 分布式测试及两个独立 OS 进程 durable-e2e 阶段均通过。

格式、warning-fatal 编译、严格 Credo、Sobelow、Gettext catalogue drift、existing-PLT Dialyzer、backend 编译通过；Server/CLI/Web 重新构建，copied/named 原生 daemon/start/RPC/pid/stop、CLI 重新挂接和 Web HTTP/资源检查通过。完整记录保存在 Trellis 的 durable-rebuild `research/final-acceptance.md` 和 durable-reference-delivery `research/independent-check.md`。

同主机 named peer 与独立进程不代表跨物理主机、断电或付费提供者保证。LSP 超时未视作通过；凭据、外部副作用与本地终止语义的边界保持不变。新事实保留策略不含自动 GC。
