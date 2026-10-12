# SPEC: Operation / Handler 契约

本文规定 Operation 的兼容性, Handler 能力与报告/回调的语义边界. 首版的逻辑接口和具体选择见
[值与消息](persistent-values-and-messages.md), [Handler 与恢复](handler-recovery-contracts.md) 和
[原子存储命令](storage-command-contracts.md).物理字段, codec 和网络传输由实现满足这些契约.

相关文档: [领域语言](../../GLOSSARY.md), [核心状态机](core-state-machines.md),
[RFC 0001](../rfc/0001-core-boundaries.md).

## 1. Operation Identity

- Operation Identity 是含兼容契约版本的稳定身份, 例如 llm.generate.v1.
- 契约包含输入, 结果与操作语义, 不等于 Handler 发布版本.
- 保持契约的修复可以不改变 Identity; 不兼容变化使用新 Identity.
- 旧 Intent 只能由兼容 Handler 解释, 不得隐式套用最新版本.
- 第一阶段不要求通用 Schema Registry 或以 Schema Hash 代替版本.
- 数据库 schema 和 Runtime 协议的迁移不是 Operation Identity 自动提供的能力.

## 2. 持久化值域

- 输入, 结果, 策略与等待数据必须符合受限, 运行时无关的逻辑值域.
- 基础值接近 JSON: 字符串, 布尔值, null, 明确范围的数字, 数组和字符串键对象.
- PID / Reference / Function / Port 等对象不得进入持久化契约. Handler 的执行内部不受此条禁止,
  但不能依赖这些对象重启后仍有意义.
- 大整数, 字节, 时间使用 Operation 定义的版本化字符串/对象, 大型产物使用稳定引用; 不设全局隐式解码.
  具体业务字段与产物保留条件由相应 Operation 确认, 基础值域由下述 v1 约束.
- 逻辑合法性, 内容等价, 存储字节与 wire 字节分别定义, 不以任意 term 可编码作为合法性判断.
- 本决策不选择具体 codec, 也不允许不受限的任意 JSON. 实际后端的数值, 文本和 round-trip 限制需要验证.

首版选择见 [持久值 v1](persistent-values-and-messages.md): 受限整数, 精确文本/结构相等, 缺省与 null 区分,
规范表示及大小/深度/节点预算; 特殊业务类型和产物生命周期由版本化 Operation 契约规定. 具体 codec 尚未实现.

## 3. Report 身份与重投

- 每个 Report 在约定作用域内有发送方提供的稳定身份.
- 重投保持身份和逻辑内容不变. 传输接收时间等本地观测信息不是发送方重新提交一份报告的依据.
- 同身份同内容: 重复接收, 不重复建立相同证据或 Outcome.
- 同身份不同内容: 协议冲突, 保留证据而不覆盖原报告.
- 不同身份同内容: 可为不同观察, 不按内容自动合并.
- 内容 hash 可以辅助检查, 不替代报告身份; 不直接以未定义稳定性的 codec 字节建立长期内容身份.
- 已持久化确认与 Outcome 接受的区别, 冲突处置和资格检查遵守核心状态机 SPEC.

首版逻辑 envelope, 来源身份域, 内容等价, 冲突保留和 Stored/DuplicateStored/ConflictStored 见
[消息契约](persistent-values-and-messages.md); 具体 wire codec/物理存储与真实认证仍待实现验证.

## 4. Handler 能力

Handler 不默认具备以下能力, 必须声明条件:

| 能力 | 需要明确的语义 |
|---|---|
| Pending | 能否建立重启后可解释的等待及关联 |
| 查询 | 可查什么, 什么证据可以确认结果或未执行 |
| 取消 | 尽力请求停止, 还是能取得确认停止的证据 |
| 幂等 | 外部去重作用域, 有效期, 输入一致性与其他前提 |
| 安全重复 | 为什么重复可接受, 或由谁明确接受重复风险 |

- 未声明的能力按不支持处理.
- 能力名称和静态布尔值不是所有时间/输入/外部环境下的保证.
- 策略根据具体条件判断是否授权重试或协调; 不能仅凭幂等声明忽略有效期.
- 声明不等于证明, 外部协议和测试仍需验证.
- 启动授权时保存实际 Handler 标识及影响恢复, 安全重试的能力条件快照. 旧尝试不只依赖当前部署的声明解释.
- 快照不保证条件永远成立, 后续重试仍需验证有效期与当前环境. 兼容实现可以参与恢复, 但不无声改变原外部协议.
- 稳定 Idempotency Context 属于 Intent, 不同 Execution 复用, 计划迁移保持不变. Handler 映射外部键和作用域,
  多步骤可按契约派生稳定子键.
- 上述上下文不等同于 Submission Key, 不给不支持幂等的目标自动增加去重保证.

协调, 规则版本, 退役和处置撤销属于后置能力. 其证据, 权限, 命令身份和原结果重投约束统一见
[核心状态机的证据协调章节](core-state-machines.md), 避免与 Handler 能力声明混合.
首版 Handler 声明/快照材料, 兼容选择, 外部 key/scope/protocol 映射及条件核验见
[Handler 契约](handler-recovery-contracts.md). 具体凭据/驱动映射待实现; 后置协调规则的登记/退役,
决定身份/取代表示和真实条件核验仍未细化.

## 5. 回调转换

- Handler 或专用回调 Adapter 验证第三方来源并解析业务内容, 再形成核心 Report.
- 核心验证 Intent / Execution 关联, Report 身份, 资格与 Operation 契约.
- 第三方未经验证的正文不直接成为 Outcome.
- 关联必须可以从持久数据恢复, 不只存在于邮箱或进程内存.
- 合法完成回调不依赖原 Worker lease 仍有效, 但仍遵守 Execution 资格与 Intent 终态规则.
- 不假定所有平台支持回调, 重投或外部状态查询.
- 回调型 Handler 最迟在启动授权提交时建立持久完成关联, 先于外部操作, 不等 Pending 报告返回.
- 合法完成报告可以先于 Pending 被处理; 迟到 Pending 不把已解决尝试退回 Waiting.
- 关联身份不等于认证凭证, 不直接使用绑定 Worker incarnation 的启动许可作为第三方回调凭证.
- 已撤权或 Closed 时仍可保存合法证据, 但不绕过资格或重新打开 Intent.

首版持久关联, 可信来源映射, 早到回调准入, 重放/重投和保留责任见
[回调契约](handler-recovery-contracts.md). 各 provider 的实际验签算法, 凭据配置和 inbox 实现须单独符合性验证.

## 6. 验收场景

1. 旧 Intent 遇到只有不兼容版本的 Handler: 不按新语义执行.
2. 嵌套值包含运行时对象: 不接受为持久数据.
3. 合法受限值在两个后端往返: 逻辑内容一致, 不要求存储字节相同.
4. Report 重投: 保持报告身份, 不重复副作用或权威结果.
5. 相同报告身份不同内容: 保存冲突证据, 不覆盖.
6. 幂等有效期已过: 不仅凭能力名授权危险重试.
7. Worker lease 已过期但外部回调合法: 验证关联与资格, 不仅因 lease 拒绝.
8. 第三方回调验证失败: 不作为可信完成证据终结 Intent.

这些是产品契约验证要求, 真实 Handler/Adapter, 受限值/codec 与 SQL 后端测试仍未实现.
[正常闭环模型](../quint/beamletNormalUse.qnt) 已增加兼容身份, 能力/协议快照, 条件幂等重试, 独立回调关联,
完成先于 Pending 与同 Intent 上下文复用的抽象场景; 真实认证, 外部窗口保证和升级协议仍须工程验证.

执行约束必须定位稳定资源并限制可用环境, 不能把另一设备的同名文件/临时会话视为原目标.
代表性 LLM, 审批, 文件和 Browser/Device 契约及新增验收要求见
[Handler 的执行环境章节](handler-recovery-contracts.md). 当前不声称这些具体驱动已经被 Quint 验证.

## 7. Intent 定义与提交身份

- 不可变定义包含 Operation Identity, 输入, 必要硬执行约束和初始策略快照.
- 当前预算, 调度节奏等控制数据另行维护, 调整需要明确受控命令与历史, 不用相同 key 的重新提交覆盖定义.
- 调整不偷偷改变操作输入, 目标或放宽副作用安全条件. 具体可调字段与权限待定.
- 同一个权威数据集合内, namespace + key 唯一定位 Intent, 不使用 Worker / 进程 / 设备身份定义作用域.
- 相同提交身份与相同原始不可变定义定位已有 Intent; 冲突定义拒绝, 不比较运行中已改变的控制状态.
- 提交确认丢失或上层重启时可重用该身份; 计划迁移保持身份. 无 key 的请求创建新逻辑操作.
- namespace 不是权限证明. Runtime 不自动识别业务等价, 上层必须保存或重建稳定提交身份.

首版定义相等, 文本精确比较, 持续身份保留和权威集合身份见 [提交消息契约](persistent-values-and-messages.md),
查找/建立的并发处理见 [存储命令](storage-command-contracts.md). 首版不提供运行中控制修改命令;
具体字段/wire codec, 部署路由及后置控制 revision 仍须实现或后续设计.

## 8. 代表性 Operation 协议样例

状态: 用于审阅统一核心的协议草案, 不是已批准的内置操作目录或 provider 支持声明.
以下 Identity 为示例; 字段均使用受限值, 资源/凭据为稳定引用, 不保存函数, PID 或凭据正文.
每个样例仍遵守授权先于调用, 可信 Report, 独立结果资格与唯一 Outcome, 不引入额外 IEO 状态.

### 8.1 `api.request.v1`: LLM / API 请求

- 不可变输入: provider/account/endpoint 引用, 请求参数, 结果解释版本; 不从当前默认账户补齐旧 Intent.
- 启动绑定: 原目标, Handler/协议版本, 外部 key 的 scope/派生与有效期; provider 请求 ID 后取得时另有早到关联协议.
- Success: 契约合法响应, 必要 provider 请求关联与正文/产物引用. LLM 正文是已完成事实, 复用不等于重生成同一文本.
- Failure: provider/Handler 明确确认的契约错误. 客户端超时, 连接中断或 HTTP 状态码本身不证明未执行.
- Pending/query/callback/idempotency 逐项按实际 provider 声明. 不支持去重或查询时, 完成与报告之间中断可能保持 Unknown.
- 验收: 同 Intent 原 key 重投, 不同 Intent key 分离, 原账户/窗口不被升级改变, 响应丢失后不盲目再收费.

### 8.2 `human.approval.v1`: 持久审批

- 不可变输入: 审批主题/材料版本, 响应者权限域和目标审批服务; 一次审批的业务身份不由在线进程生成.
- 启动前保存 correlation 与核验协议. 首次建立外部审批后形成 Pending; 外部创建与绑定不能原子时,
  服务须接受预分配关联, 或 Adapter 提供满足原子保存/重放要求的 inbox, 不能先创建再仅记在邮箱.
- 结果为 `{decision: "approved" | "denied", approval_ref: ..., decision_ref: ...}` 的逻辑对象,
  两种选择均为 Success; 对响应者无权, 缺少原审批或正文格式错误, 不形成可信完成.
- 原审批的合格决定须由服务协议提供稳定身份与不可覆盖的查询/回调证据. 两份合法矛盾决定保留冲突,
  不按最新消息或最高接收时间选定. UI 已展示, 已点击或通知已送达均不等于 Outcome.
- 所有进程退出后查询/回调仍定位原审批; 创建响应丢失不能无条件再开一份审批.
  Runtime 等待超时不等于 denied; 若业务需要过期结果, 另行定义服务证明与 Operation 语义.
- 验收: 拒绝为正常结果, 完成先于 Pending, 原 Worker 丢失后完成, 无权响应拒绝, 矛盾事件不覆盖.

### 8.3 `file.replace_if_version.v1`: 条件替换文件对象

- 不可变输入: 设备/volume/object 稳定引用, expected_version, 新内容的稳定引用与完整性摘要.
  裸路径仅能在该资源域内解析, 不能把另一设备同名路径当成原对象.
- 声明支持的资源协议须原子检查对象版本并完成条件修改. 结果可为
  `{applied: true, object_ref: ..., version: ..., digest: ...}` 或契约定义的
  `{applied: false, reason: "version_mismatch"}`; 二者是本样例的正常 Success 数据, 不把业务条件未满足猜成基础设施
  Failure.
- 若宣称完成后可恢复, 资源协议须保留与原操作 key 绑定的 receipt/查询依据,
  或提供其他可证明结果的机制. 本地 rename, mtime, 当前内容相同均不自动提供此依据.
- 不默认文件系统具有版本 CAS, receipt 与业务写入原子保存, 跨 volume 原子性或持久幂等.
  缺少声明条件时不能提供本样例的强协议; 可另定义较弱 Operation 并披露 Unknown 风险.
- 验收: 错设备/对象不调用, 两个 Intent 竞争同一版本按资源协议处理,
  写入后报告前崩溃按 receipt 恢复或保持 Unknown, 不借重试覆盖他人新版本.

### 8.4 `device.command.v1`: Browser / Device 动作

- 不可变输入: 稳定设备/账户/会话引用, 目标对象, 动作及前置条件; 临时 tab ID 不能是唯一恢复材料.
- 绑定到合格环境并在调用前重验. 会话不能重建则保持资源不可用/既有事实, 不换到默认浏览器继续动作.
- Success 必须有契约合格的动作完成证据及必要结果. 页面状态符合期望可能由其他操作造成,
  不能仅凭它证明原付款/点击/设备命令已经完成; 若目标状态本身就是目标, 应另定义该语义的 Operation.
- 无外部 key/receipt/query 保证的不可逆动作, 连接中断后保持 Unknown, 不以 UI 自动化的可重放脚本推导安全重试.
- 验收: 会话丢失, 错账户/设备拒绝, 相同页面不替代原证据, 已获许可旧会话可能仍运行,
  取消只终结 Intent, 不伪造资源已停止.

这些样例检验 IEO 的共性与外部协议的差异, 不构成具体资源实现的验证.
上述强条件并非要求所有文件/API 都具有这些能力; 弱能力操作必须显式保留相应的不确定性.
资源绑定与恢复时限的共同要求仍以 [Handler 契约](handler-recovery-contracts.md) 为准.
