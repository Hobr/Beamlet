# Beamlet 执行领域

## Language

**Node**:
承载基础设施和业务角色实例的运行容器, 不因承担网络监听而获得执行授权权力.

**Client**:
表达执行意图并读取接纳状态和结果的参与方, 不负责创建执行授权.

**Authority**:
持有 Operation 权威记录, 决定执行授权并收录执行证据的角色.

**Worker**:
接纳指定 Authority 的执行授权, 执行工作并保留执行证据的角色.
_Avoid_: Work, Runner 作为对外角色名

**Operation**:
具有独立身份的不可变逻辑请求, 相同任务内容不代表同一请求.

**Attempt**:
针对指定 Operation 的一次执行授权, 不是消息投递次数.

**Report**:
有关一次授权执行的证据, 独立于 Authority 是否采用及业务是否成功.

**SubmissionKey**:
在指定 Authority 内关联同一次提交的稳定去重键, 不等于 Operation 的身份.

**角色实例**:
角色的一次运行身份, 与跨启动保持的逻辑角色身份不同.
