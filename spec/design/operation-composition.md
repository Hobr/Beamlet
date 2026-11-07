# Operation 组合与 Agent Loop

状态: 设计契约, 尚未实现. 本文不新增 Task 实体, crate, 网络协议或通用注册框架. 当前 `beamlet-agent::Agent` 仍只是 Authority/Worker 本地组合, 不具备本文的 LLM Loop, capability 调用, 来源关联或派生提交映射. 已实现的内存交付保证见 [三段回执契约](receipts.md).

## 范围与概念

Agent 和 Codemode 是执行逻辑, 不是新增参与方. 一次完整 Agent 或 Codemode 执行由 Operation 表达, 接纳后通过 Attempt 授权给 Worker, 返回自身 Report. 执行期间可以使用受限的 Client 能力提交其他 Operation. 不新增 TaskId 或另一套生命周期账本.

Operation capability 定义可调用行为的契约, 包括目标绑定, 输入输出和权限要求. capability 的一次调用由 Operation 表达. capability 可承载 LLM, Codemode, 文件读取, Shell 或本地计算; 不要求全部返回同一种业务输出. Agent 集成组合并向执行方提供获准 capability, 注册或获得调用名称本身不代表获准执行.

所有显式暴露的可调用计算都经过 Operation, 包括拼接, 过滤和解析, 不因无外部效果或同进程执行而绕开授权与证据. 执行器内部的语言求值, 协议解码和账本状态转换不是自动派生 Operation 的规则, 不将每个内部指令递归转换为新请求. 同进程可类型化直接交付, 仍保留相同接纳及校验语义.

## 完整 Loop 与最小调用链

本文选择完整 Agent Loop: Agent 的最终 Report 表示本次 Loop 已返回, 不是要求外部继续执行的中途行动计划. 单步决策可以作为另一种明确命名的 capability, 但不混用两种完成契约.

```text
Client -> Agent Operation A, Attempt A1
          |
          +-> LLM Operation L1, Attempt L1-1
          |     -> Report LR1: 完整输出, 含 read_file 调用块 0
          |
          +-> 文件读取 Operation F, Attempt F1
          |     -> Report FR: 读取结果或失败证据
          |
          +-> 上下文组装 Operation P, Attempt P1
          |     -> Report PR: 选定的上下文及证据引用
          |
          +-> LLM Operation L2, Attempt L2-1
          |     -> Report LR2: 最终答案, 没有待处理的调用请求
          |
          +-> Agent Report AR: 最终结果及实际采用的证据引用
```

A1 的执行逻辑负责校验 LR1 的调用请求, 提交 F, 选择相关 Report 组装下一轮输入, 最终返回 AR. LR1 的成功只表示 LLM capability 返回了符合契约的输出, 不表示工具调用已被授权或执行. LR2 是否足以结束 Loop 由明确的策略决定, 不只靠文本非空判断.

示例将上下文组装作为显式 capability 调用 P, 故同样经过 Operation. P 可省略无关过程, 不能删除原执行证据或篡改 Report. 是否采用一段文本, 某个 Report 或某个调用结果是组合层决策, 不是 Kernel 的自动行为.

Codemode 调用遵循相同机制. 若 LR1 请求 Codemode, A1 提交 Codemode Operation C; C 的执行再提交 F 等 Operation, 聚合后返回 C 自己的 Report. 对 LLM 可以只返回 C 的选定结果, 不要求展开 C 的全部内部调用. 不增加 Codemode 专用授权层.

## 输入输出草案

以下类型说明组合层的数据职责, 不是可编译的公共 Rust Interface 或新增 v0 编码. `Value` 表示 Adapter 的业务值, 不引入纯 Kernel. 当前 `Operation<P>.task` 继续是泛型不可变请求定义, 字段名不意味着存在 Task 实体.

```text
Invocation {
  capability: CapabilityRef,
  input: Value
}

LlmOutput {
  blocks: [Text | ReasoningSummary | Call],
  completion: Complete | Incomplete
}

Call {
  provider_call_id: String,
  invocation: Invocation
}

ExecutionRef {
  authority_instance_id: AuthorityInstanceId,
  operation_id: OperationId,
  attempt_id: AttemptId
}

ReportPartRef {
  authority_instance_id: AuthorityInstanceId,
  report_id: ReportId,
  block_index: u32
}

InvocationOrigin {
  submitted_by: ExecutionRef,
  call_slot: LocalCallKey,
  triggered_by: Optional<ReportPartRef>
}
```

`CapabilityRef` 必须明确被授权的行为版本及目标绑定, 不能只凭 LLM 输出的任意字符串直接选择执行器. 具体表示留到最小实现时决定. LLM 请求输入包含明确的模型配置及已组装上下文, 不依赖隐式可变的全局对话; 提供方凭据由 Adapter 管理, 不把凭据写入执行记录或模型上下文.

提供方 Adapter 将输出规范化为有序块, 可同时包含文本和多个调用. 仅保留提供方明确返回的推理内容或摘要, 不保证获取模型内部推理. 流式片段不直接作为可执行调用或最终 Report; 截断, 未完成参数或不支持的输出不得被当成完整工具请求执行.

`provider_call_id` 只在所属模型输出范围内关联调用和工具回复. 不替代 OperationId, SubmissionKey 或框架内的调用位置. `block_index` 指规范化后不可变 Report 输出中的位置, 不能在筛选文本后重新编号. 提供方调用标识缺失或重复而不能无歧义回填时, 应拒绝该输出的自动调用处理, 不猜测对应关系.

Agent 最终输出可包含选定结果和证据引用; 不要求是字符串, 也不要求所有 capability 使用包含全部业务类型的核心枚举. 输出类型或编码标签属于对应 capability 的契约.

## 两种关联

| 新提交 | 执行来源 submitted_by | 触发依据 triggered_by |
| --- | --- | --- |
| L1 | A / A1 的 ExecutionRef | 无, 由 Loop 策略发起 |
| F | A / A1 的 ExecutionRef | LR1 的调用块 0 |
| P | A / A1 的 ExecutionRef | 无; 实际使用的 LR1/FR 等另行记录为输入证据 |
| L2 | A / A1 的 ExecutionRef | 无; 上下文明确引用 PR |
| C, 若由 LR1 请求 | A / A1 的 ExecutionRef | LR1 中对应 Codemode 调用块 |
| C 内部提交的 F | C / 对应 Attempt 的 ExecutionRef | 直接代码调用可无触发 Report |

执行来源说明实际由哪个运行中的授权执行发起提交. 触发依据说明哪份输出中的哪项请求引出了该提交. LLM Operation 可以已经结束, 因而不能把工具 Operation 误记为仍运行的 LLM Attempt 主动提交.

`call_slot` 区分同一执行发起的独立调用, 不按参数内容命名. 无 LLM Report 触发的 Codemode 直接调用也必须有位置, 例如宿主在提交前分配并记录的调用序号. 重传复用该位置; 循环的不同迭代和两个相同参数调用使用不同位置. 它不是新的全局业务身份, 也不承诺仅凭序号就可安全重放代码.

上下文实际采用哪些 Report 是数据依赖, 不与上述任一种关系等同. 一个 Operation 可以使用多份证据, 不强制把全部关系压成单个 parent_id 或一棵树. 也不沿调用链重复复制所有祖先的元数据.

来源和触发依据由宿主绑定并校验, 不能信任 LLM 自报身份. 它们不授予权限, 不转移 Operation 所有权, 不隐含取消传播或结果采用. 每个 Operation 仍由明确的 Authority 独立接纳. 跨 Authority 引用保留归属, 不因此获得查询权或跨 Authority 原子事务保证.

关联随新提交接纳一起保留, 不事后修改原 Operation 请求或追加 children 数组. 反向查询可以从已保留关联派生, 不要求两份可变关系列表同步更新. 本文尚未决定字段落在具体哪一层, 不宣称当前提交协议已经保存这些关联.

## 从 Report 派生提交

1. 在组合层选择并记录本轮要消费的完整 LLM Report. 校验它属于预期 Operation/Attempt, 是合法输出, 且所引用调用块存在. Report 收录不自动触发执行.
2. 校验 capability 是否可用, 参数是否符合契约, 目标和调用权限是否匹配, 执行及资源预算是否足够. 模型输出只是提议, 不生成自授权 Attempt.
3. 为通过校验的每个独立调用, 在任何发送前预留有界的派生记录, 保存完整 Invocation, 来源, 触发依据, 目标 Authority 和一个稳定 SubmissionKey. 不能每次处理 Report 都生成新 key.
4. 经现有接纳流程提交, 未确认时保留原 key 与定义, 不伪造 OperationId. Authority 接纳后关联其返回的原 Operation/Attempt; 观察超时不代表未接纳.
5. 保留工具 Report 与调用块的对应关系, 由上下文组装明确选择数据. 如需继续调用 LLM, 提交新的 LLM Operation; 不修改上一份 LLM 请求或 Report.

同一调用的派生记录按执行来源和 call_slot 定位, 并校验触发依据. 同一个已选 LLM 调用块必须复用其已记录位置, 不能每次消费分配新位置. 相同记录重入复用完整原映射; 相同身份配不同定义或不同来源不能静默覆盖. 两个位置不同但参数相同的调用是两个独立请求, 不按内容去重. 新一轮或另一份独立授权执行的相同内容也不自动合并.

消费记录必须冻结本轮已选 Report, 不因重复交付或附加 Report 自动选择另一份输出再执行一遍. 附加证据仍被收录, 但是否用于后续决策需显式策略; 不能把收录本身解释成新的执行指令. 工具错误和部分调用拒绝应成为明确的调用观察或策略输入, 不捏造 Tool Report.

派生记录及消费记录需要各自的数量与字节上限. 容量不足时在发起新调用前停止, 不淘汰去重记录来恢复可执行预算. 本设计先约束同进程内重入与重传; 没有持久记录时不能声称可在崩溃后重跑 Loop 而不重复产生效果. Worker 丢失派生 key 后, 不得用新 key 自动重建未确认调用.

## 上下文与完成条件

执行证据和 LLM 上下文是两种视图. 默认可只投影 Codemode 汇总结果, 不展开其内部全部调用. 若保留模型的调用请求, 就必须按提供方协议保留对应的调用结果或明确的未确认观察, 不产生悬空调用标识. 不把成功, 失败, 拒绝及 Effect 未知都压成成功文本. 输出摘要不能改写原 Report 或抹掉外部效果.

Agent 正常成功默认要求本次策略所需的调用已有可用证据, 结果已完成组装, 且没有被忽略的必需调用. 输出混有调用请求的文本不自动视为最终答案. 不以固定轮数或等待超时伪造完成; 预算耗尽可以停止 Loop 并返回真实失败或部分结果, 但必须明确仍未确认的下游执行. 无界 Loop 不属于本阶段实现目标.

Agent Report 与其子 Operation 的 Report 独立. Agent 失败不回滚工具效果, 取消等待不证明工具停止, Agent 返回之后迟到证据仍应保留. Agent 的 Effect 必须按所声明的执行范围和实际证据决定, 不能因为代码只做编排就报告 None, 也不能仅从成功或失败推导效果. 本文不定义未经证明的自动 Effect 聚合算法.

同一 Worker 池里等待子 Operation 不能占满这些子执行必需的全部槽位. 最小实现可先采用明确分开的执行容量, 但不能仅凭 async 等待就声称没有资源死锁. 这项调度能力尚未实现.

## 验收与后续边界

后续最小实现应以本调用链验证: 正常工具闭环, 同 Report 重复消费只派生一次, 同参数不同调用分别执行, 附加证据不自动重跑, 参数或权限拒绝, 部分工具失败, 接纳回执缺失后复用 key, Agent 结束后的迟到证据, 父执行等待时子执行仍能取得容量. 不新增仓库测试用例, 运行现有测试并使用临时真实进程探针补充验收.

本批仅固定上述语义和输入输出职责. 下一实现目标是最小类型化嵌套提交路径及有界派生映射, 先用固定 LLM 输出和假工具验证, 不接真实模型或文件效果. 暂不新增 beamlet-task, Task 生命周期, 自主多 Agent 调度, 通用 capability 注册表, Workflow DSL, 数学组合引擎或持久恢复. Client Interface 的提取应以这一实际组合路径为依据.
