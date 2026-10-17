# Beamlet 领域术语

统一 Agent、Operation 与执行历史的领域用语。持久化相关术语属于[持久化设计](./docs/architecture/agent-operation-persistence.md)，不表示功能已经实现。

## Language

**Agent**：具有明确权威归属、维护对话与决定下一步工作的推理主体。
_Avoid_：Worker、Execution、Elixir Agent 状态容器

**Authority（权威）**：拥有某个 Agent 或独立 Operation 的业务状态与决定权的节点。
_Avoid_：全局主节点、执行节点

**Operation（操作）**：一次提交所请求工作的结构化描述，其请求含义在提交后固定。
_Avoid_：Intent、Invocation、自然语言目标

**Execution（执行尝试）**：为执行某个 Operation 而分配身份的一次尝试，包括尚未确认准入的情况。
_Avoid_：Worker 进程、Operation 的别名

**Result（结果值）**：描述成功、失败、拒绝、取消、超时或不确定等终态的共享值；只有被权威接受后才成为该 Operation 的终态事实。
_Avoid_：独立结果实体、进度、取消请求

**Execution evidence（执行证据）**：执行节点对准入、启动意图或完成情况保存的观察，可供权威核对；不等同于已接受的 Result。
_Avoid_：外部副作用证明、第二份权威状态

**Result acceptance（结果接受）**：权威为某个 Operation 确认唯一终态值的决定。
_Avoid_：结果到达、结果消费

**Result consumption（结果消费）**：Agent 将已接受的结果或显式采纳的证据纳入某个 Agent 上下文的决定。
_Avoid_：再次执行、结果接受

**Checkpoint（检查点）**：足以重建 Agent 有效上下文与继续位置的已保存状态。
_Avoid_：进程快照、环境快照

**Continuation（继续位置）**：说明 Agent 下一步应等待、转换或请求什么工作的明确位置。
_Avoid_：可执行闭包、自动重试指令

**Recovery（恢复）**：利用已保存事实重建可审阅、可控制的 Agent 状态；是否继续工作是另一个决定。
_Avoid_：重执行、自动故障转移

**Reconciliation（证据核对）**：查询并关联已有执行证据以解释未决工作，不创建新的执行尝试。
_Avoid_：重试、重新派发

**Fork（派生）**：从安全检查点复制有效上下文，创建具有独立身份和历史的新 Agent；原 Agent 保持独立。
_Avoid_：同一 Agent 的分支切换、执行历史重放

**Rewind（回撤）**：选择较早的安全检查点派生新 Agent，作为后续推理的起点。
_Avoid_：外部环境回滚、撤销副作用

**Trace（轨迹）**：对已观察输入、决策、请求、结果和相关因果关系的记录。
_Avoid_：模型私有思维链、保证相同输出的重放脚本
