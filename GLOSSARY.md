# Beamlet 领域语言

Beamlet 是 Effect Engine 的名称, 定位为 Distributed Durable Effect Runtime.
Beamlet!!!!! 是基于 Beamlet 的 Agent 框架及其系列产品的名称.
本词汇表主要定义引擎层的外部操作, 执行尝试与权威结果, 不描述具体存储或通信实现.

## Language

**Beamlet**:
Effect Engine 的名称, 涵盖核心 Effect 系统及其运行时, 不指代上层 Agent 框架或产品系列.
_Avoid_: 用 Beamlet 指代 Beamlet!!!!!

**Beamlet!!!!!**:
基于 Beamlet 的 Agent 框架及其系列产品的名称, 五个感叹号是名称的一部分.
_Avoid_: 省略或改变感叹号数量, 用 Beamlet!!!!! 指代引擎

**Effect**:
对需要外部环境完成的操作的可持久化描述, 其执行与结果不依赖发起计算继续存活.
_Avoid_: 可恢复函数, Continuation

**Operation Identity**:
一个外部操作契约的稳定身份, 包含其兼容版本, 用于解释输入, 结果与操作语义. 它不等同于某次请求身份或 Handler 代码发布版本.
_Avoid_: Content Hash, Handler 最新版本

**Intent**:
一个具有独立身份的逻辑外部操作请求, 其操作定义不可变. 相同输入可以属于不同 Intent.
_Avoid_: Execution, 按输入去重的操作

**Execution**:
属于某个 Intent 的一次执行尝试. 建立 Execution 不表示外部操作已经开始, 其结果也不必被接受为 Outcome.
_Avoid_: Intent, 权威结果

**Eligible Execution**: 在尚未终结的 Intent 中, 满足正常结果接受资格的执行尝试. 资格不等于成功, Worker 存活或 lease
未到期, 也不表示报告必然会被采用. _Avoid_: 执行成功, 活跃 Worker

**Start Authorization**:
Authority 对某个 Execution 在外部执行前授予的启动许可. 取得许可意味着操作可能随后发生, 不证明操作已经开始或完成.
_Avoid_: 实际外部开始, 执行成功

**Outcome**: Beamlet 为某个 Intent 接受的不可变权威结果, 分类为 Succeeded, Failed 或 Cancelled, 每个 Intent
最多拥有一个. 它不等同于对外部世界全部副作用的证明. _Avoid_: Execution 的报告结果, 外部执行恰好一次

**Report**:
Handler, Worker 或协调过程提交的操作进展或结果证据. Report 可以被保存而未被采用为 Outcome, 也不自动证明其内容没有争议.
_Avoid_: Outcome, 可覆盖的最终结果字段

**Unreconciled Conflict**: 已收到的证据之间存在尚未由 Authority 协调解决的争议, 阻止未经协调的自动结果采用. 它与
Execution 的生命周期和结果资格分别表达. _Avoid_: Conflicted 生命周期状态, 最后一份报告覆盖结果

**Reconciliation**: Authority 按 Operation 契约审查不确定, 矛盾或失去直接结果资格的证据, 明确其如何影响 Intent
的处理与终结. 它不等同于直接重试或改写原始报告. _Avoid_: 强制重执行, 覆盖证据

**Reconciliation Decision**: Authority 对具体证据如何影响某次 Intent 判断作出的明确处置,
包括采用或排除及其契约依据, 理由与处理主体. 协调矛盾报告时须明确处理本次判断相关的完整冲突.
可以按契约排除全部相关报告并完成审查, 同时保持实际结果未知; 这不产生终结结果或自动重试许可. 它不改写原始报告,
也不自动处置未来证据. _Avoid_: 永久已协调标志, 任意结果覆盖

**Rule Semantic Version**: 标识某项自动协调规则采用哪一套判断语义的版本, 与规则身份一起解释自动决定的依据.
历史决定按当时版本解释; 新提交须核验指定版本的登记和适用条件. _Avoid_: 代码发布版本, 默认最新规则, Judgment Revision

**Rule Retirement**:
停止接受某项自动协调规则语义版本的新决定, 不自动撤销其已接受处置. 历史决定, 原命令结果与已提交 Outcome 仍保留原含义.
_Avoid_: 撤销既有处置, 删除规则历史, Outcome 撤回

**Supersession**: 新协调决定对先前证据处置的明确取代关系, 指出被取代的旧处置和对应范围. 旧决定仍是审计事实,
原命令仍返回原处理结果; 取代不影响范围外的处置或改写已有 Outcome. _Avoid_: 最后写入覆盖, 删除旧决定, Outcome 替换

**Disposition Withdrawal**: 明确撤除指定范围的当前证据处置, 使该范围重新等待判断, 而不恢复更早被取代的处置.
它不删除历史决定, 改写原命令结果或撤回已有 Outcome. _Avoid_: 恢复上一版结论, 删除决定, 规则退役, Outcome 撤销

**Reconciliation Command Identity**: 在一个 Intent 内标识同一协调或处置撤销请求的稳定身份,
用于识别重投并定位原成功或明确领域拒绝结果. 操作种类不同不产生另一身份域, 新判断或新撤销不沿用已处理身份.
_Avoid_: Submission Key, Report ID, 永久协调权限

**Judgment Revision**: 标识某个 Intent 的判断材料与资格处于哪一版的单调编号, 用于检测审查后, 提交前发生的相关变化.
版本相同仍须验证决定的证据, 契约和权限. _Avoid_: 代码版本, 墙钟时间, 全部状态变化计数, 命令 ID

**History**:
Beamlet 保存的状态变化与重要决定的审计事实集合, 用于解释操作如何被处理. 它不是必须重放才能恢复当前权威状态的事件源.
_Avoid_: 普通日志全集, Event Sourcing 日志

**Intent Cancellation**:
Authority 接受取消结果后对 Intent 的逻辑终结, 不表示外部操作已经停止或被回滚. 请求取消与取消已被接受是不同事实.
_Avoid_: 外部副作用回滚, Worker 已停止

**Authority**:
对某个 Intent 的关键生命周期变化与 Outcome 接受拥有唯一逻辑裁决权的主体. 它不等同于某个固定进程或设备.
_Avoid_: 全系统唯一中心节点, Worker

**Planned Authority Transfer**: 在旧 Authority 可配合交接的情况下, 将某个 Intent 的唯一逻辑裁决权交给新的 Authority.
它不等同于复制数据, 也不包含旧 Authority 不可达时的强制接管. _Avoid_: 数据备份, 自动故障接管

**Submission Key**: 调用方在约定权威数据域内以 namespace + key 指定的稳定提交身份, 用于重新定位同一个 Intent.
它不等同于目标服务用于外部操作去重的键. _Avoid_: 输入 hash, 外部 Idempotency Key

**Idempotency Context**: 属于一个 Intent, 可由多次 Execution 复用的稳定逻辑幂等上下文. Handler 将其映射到外部协议,
但它本身不保证目标服务能够去重. _Avoid_: Submission Key, 每次尝试新建的去重身份

**Effect-level Recovery**:
依据已持久化的外部操作事实继续处理操作或复用已有 Outcome 的恢复方式. 它不包含任意控制流或 Agent 上下文的自动重建.
_Avoid_: 调用栈恢复, 完整 Agent Recovery
