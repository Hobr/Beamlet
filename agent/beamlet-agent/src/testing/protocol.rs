//! 固定假任务的 v0 JSON 测试 Adapter, 与领域对象显式转换

/// 身份定义来自纯 Kernel; UUID 字符串编码仅由本 Adapter 实现
pub use crate::id::{AttemptId, OperationId, ReportId, RoleInstanceId};
use crate::model as domain;
use serde::{Deserialize, Serialize};
/// 不透明 JSON 测试数据
pub use serde_json::Value;
use thiserror::Error;
/// 测试和启动方的 UUID 工具, 纯 Kernel 不依赖此库
pub use uuid::Uuid;

/// 此实验性协议唯一支持的传输版本
pub const PROTOCOL_VERSION: u16 = 0;

/// 显式资源上限; 默认值仅用于原型, 不是经过测量确定的资源预算
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub struct Limits {
    /// 序列化消息信封的最大长度, 包含头部与 JSON 数据
    pub max_message_bytes: usize,
    /// 固定延迟任务允许的最大延迟毫秒数
    pub max_delay_ms: u64,
    /// 各请求, 执行授权或报告记录表分别允许保留的最大身份数量
    pub max_records: usize,
    /// 每个 Worker 中已接纳但尚未开始的 Attempt 数量上限
    pub queue_capacity: usize,
    /// 每个 Worker 中标记为运行中的 Attempt 数量上限
    pub max_concurrency: usize,
}

impl Default for Limits {
    fn default() -> Self {
        let runtime = beamlet::memory::Limits::default();
        Self {
            max_message_bytes: 64 * 1024,
            max_delay_ms: 60_000,
            max_records: runtime.max_records,
            queue_capacity: runtime.queue_capacity,
            max_concurrency: runtime.max_concurrency,
        }
    }
}

impl Limits {
    /// 检查数量与字节上限是否允许系统推进
    ///
    /// # 错误
    /// 数量或字节上限为零时返回错误. 延迟上限允许为零,
    /// 此时延迟任务只能使用零毫秒延迟
    pub fn validate(&self) -> Result<(), ProtocolError> {
        if self.max_message_bytes == 0
            || self.max_records == 0
            || self.queue_capacity == 0
            || self.max_concurrency == 0
        {
            return Err(ProtocolError::InvalidLimits);
        }
        Ok(())
    }
}

/// 固定测试数据, 不是能力注册或插件接口
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(
    tag = "kind",
    content = "input",
    rename_all = "snake_case",
    deny_unknown_fields
)]
#[non_exhaustive]
pub enum TestTask {
    /// 返回提供的 JSON 数据
    Echo(Value),
    /// 在受限延迟后返回数据; 协议层仅定义数据, 不执行等待
    Delay {
        /// 请求的非负延迟毫秒数
        delay_ms: u64,
        /// 延迟结束后返回的数据
        value: Value,
    },
    /// 返回测试错误, 不调用外部工具
    Fail {
        /// 测试驱动提供的错误文本
        message: String,
    },
}

/// v0 的空约束; 出现未知约束字段时, JSON 解码失败
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
#[non_exhaustive]
pub struct Constraints {}

/// 客户端提供的不可变请求
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
#[non_exhaustive]
pub struct SubmitOperation {
    /// 重复提交时复用的稳定身份标识
    #[serde(with = "identity_json")]
    pub operation_id: OperationId,
    /// 三种固定测试任务之一
    pub task: TestTask,
    /// 仅支持 v0 的空约束集合
    pub constraints: Constraints,
}

impl SubmitOperation {
    /// 使用 v0 的空约束构造请求
    pub fn new(operation_id: OperationId, task: TestTask) -> Self {
        Self {
            operation_id,
            task,
            constraints: Constraints::default(),
        }
    }
}

/// 携带完整且不可变 Operation 定义的一次执行授权
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
#[non_exhaustive]
pub struct DispatchAttempt {
    /// 重复交付同一授权时复用的身份标识
    #[serde(with = "identity_json")]
    pub attempt_id: AttemptId,
    /// 原始请求, 包含其 Operation 身份
    pub operation: SubmitOperation,
}

/// 有关外部效果的证据, 与执行成功或失败相互独立
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum Effect {
    /// 证据确认没有产生外部效果
    None,
    /// 已观察到外部效果, 但不代表效果完整或只发生一次
    Observed,
    /// 现有证据无法确定是否产生了外部效果
    Unknown,
}

impl std::fmt::Display for Effect {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::None => "无外部效果",
            Self::Observed => "已观察到效果",
            Self::Unknown => "效果未知",
        })
    }
}

/// 通过类型约束, 避免输出与错误字段同时存在的执行结果
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "outcome", rename_all = "snake_case", deny_unknown_fields)]
#[non_exhaustive]
pub enum ExecutionResult {
    /// 处理函数返回了输出
    Succeeded {
        /// 处理函数的输出, 不代表 Authority 的采用决定
        output: Value,
    },
    /// 处理函数失败; 外部效果仍可能未知, 或已经被观察到
    Failed {
        /// 长度受限的错误文本
        error: String,
    },
    /// 执行器拒绝运行处理函数
    Rejected {
        /// 拒绝运行的原因, 不表示传输交付情况
        error: String,
    },
}

/// 由绑定的 Worker 运行实例发给其 Authority 的执行证据
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[non_exhaustive]
pub struct SubmitReport {
    /// 重复交付此证据时复用的身份标识
    #[serde(with = "identity_json")]
    pub report_id: ReportId,
    /// 此证据所属的 Operation
    #[serde(with = "identity_json")]
    pub operation_id: OperationId,
    /// 本次尝试执行所依据的授权
    #[serde(with = "identity_json")]
    pub attempt_id: AttemptId,
    /// 外部效果证据, 不从处理函数的执行结果推断
    pub effect: Effect,
    /// 执行结果平铺为传输中的 outcome, output 或 error 字段
    #[serde(flatten)]
    pub result: ExecutionResult,
}

impl SubmitReport {
    /// 构造与给定执行授权关联的证据
    pub fn for_attempt(
        report_id: ReportId,
        attempt: &DispatchAttempt,
        effect: Effect,
        result: ExecutionResult,
    ) -> Self {
        Self {
            report_id,
            operation_id: attempt.operation.operation_id,
            attempt_id: attempt.attempt_id,
            effect,
            result,
        }
    }
}

/// v0 原型支持的全部业务消息类型
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(
    tag = "kind",
    content = "body",
    rename_all = "snake_case",
    deny_unknown_fields
)]
#[non_exhaustive]
pub enum Message {
    /// 客户端发给 Authority 的请求
    SubmitOperation(SubmitOperation),
    /// Authority 发给 Worker 的执行授权
    DispatchAttempt(DispatchAttempt),
    /// Worker 回报给 Authority 的执行证据
    SubmitReport(SubmitReport),
}

/// 以进程运行实例为范围的消息信封; 头部不构成发送方身份认证
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
#[non_exhaustive]
pub struct Envelope {
    /// 必须等于当前支持的协议版本
    pub protocol_version: u16,
    /// 发送方进程的本次运行实例
    #[serde(with = "identity_json")]
    pub source_instance_id: RoleInstanceId,
    /// 目标接收进程的本次运行实例
    #[serde(with = "identity_json")]
    pub target_instance_id: RoleInstanceId,
    /// 具有明确类型的业务消息
    pub message: Message,
}

impl Envelope {
    /// 使用当前支持的传输版本构造消息信封
    pub fn new(source: RoleInstanceId, target: RoleInstanceId, message: Message) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            source_instance_id: source,
            target_instance_id: target,
            message,
        }
    }

    /// 仅序列化符合原型资源限制的消息信封
    ///
    /// # 错误
    /// 不支持的版本, 无效上限或效果组合, 超限延迟,
    /// 超大消息及 JSON 编码失败都会返回错误
    pub fn to_json(&self, limits: &Limits) -> Result<Vec<u8>, ProtocolError> {
        self.validate_content(limits)?;
        let bytes = serde_json::to_vec(self)?;
        if bytes.len() > limits.max_message_bytes {
            return Err(ProtocolError::MessageTooLarge);
        }
        Ok(bytes)
    }

    /// 解析前检查大小, 并拒绝未知的消息或约束字段
    ///
    /// # 错误
    /// JSON 超限, 格式错误或消息内容无效时返回错误
    pub fn from_json(bytes: &[u8], limits: &Limits) -> Result<Self, ProtocolError> {
        limits.validate()?;
        if bytes.len() > limits.max_message_bytes {
            return Err(ProtocolError::MessageTooLarge);
        }
        let envelope: Self = serde_json::from_slice(bytes)?;
        envelope.validate_content(limits)?;
        Ok(envelope)
    }

    /// 在内存状态转换前校验本地构造的数据
    ///
    /// # 错误
    /// 返回与 [`Self::to_json`] 相同的校验错误
    pub fn validate(&self, limits: &Limits) -> Result<(), ProtocolError> {
        self.to_json(limits).map(|_| ())
    }

    fn validate_content(&self, limits: &Limits) -> Result<(), ProtocolError> {
        limits.validate()?;
        if self.protocol_version != PROTOCOL_VERSION {
            return Err(ProtocolError::UnsupportedVersion(self.protocol_version));
        }
        let operation = match &self.message {
            Message::SubmitOperation(operation) => Some(operation),
            Message::DispatchAttempt(attempt) => Some(&attempt.operation),
            Message::SubmitReport(report) => {
                core_report(report)
                    .validate()
                    .map_err(|_| ProtocolError::InvalidRejectionEffect)?;
                None
            }
        };
        if let Some(SubmitOperation {
            task: TestTask::Delay { delay_ms, .. },
            ..
        }) = operation
            && *delay_ms > limits.max_delay_ms
        {
            return Err(ProtocolError::DelayTooLarge);
        }
        Ok(())
    }
}

/// 实验性协议接口的解码与校验错误
#[derive(Debug, Error)]
#[non_exhaustive]
pub enum ProtocolError {
    /// 数量或字节上限为零
    #[error("资源上限必须为正数")]
    InvalidLimits,
    /// 整个消息信封超过配置的字节上限
    #[error("消息超过配置的字节上限")]
    MessageTooLarge,
    /// 接收方不支持此传输版本
    #[error("不支持的协议版本 {0}")]
    UnsupportedVersion(u16),
    /// 延迟超过配置的最大值
    #[error("延迟超过配置的最大值")]
    DelayTooLarge,
    /// 执行前的拒绝不能同时声称可能产生了外部效果
    #[error("执行前拒绝必须确认没有外部效果")]
    InvalidRejectionEffect,
    /// JSON 格式错误, 或不符合严格的消息结构
    #[error("协议 JSON 无效: {0}")]
    Json(#[from] serde_json::Error),
}

mod identity_json {
    use serde::{Deserialize, Deserializer, Serialize, Serializer};
    use uuid::Uuid;

    pub fn serialize<I: Copy + Into<u128>, S: Serializer>(
        value: &I,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        Uuid::from_u128((*value).into()).serialize(serializer)
    }

    pub fn deserialize<'de, I: From<u128>, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<I, D::Error> {
        Ok(Uuid::deserialize(deserializer)?.as_u128().into())
    }
}

/// 已知空约束只存在于 v0 格式, 不进入通用请求定义
pub(crate) fn core_operation(value: &SubmitOperation) -> domain::Operation<TestTask> {
    domain::Operation {
        operation_id: value.operation_id,
        task: value.task.clone(),
    }
}

pub(crate) fn core_report(value: &SubmitReport) -> domain::SubmitReport<Value, String> {
    domain::SubmitReport {
        report_id: value.report_id,
        operation_id: value.operation_id,
        attempt_id: value.attempt_id,
        effect: match value.effect {
            Effect::None => domain::Effect::None,
            Effect::Observed => domain::Effect::Observed,
            Effect::Unknown => domain::Effect::Unknown,
        },
        result: match &value.result {
            ExecutionResult::Succeeded { output } => domain::ExecutionResult::Succeeded {
                output: output.clone(),
            },
            ExecutionResult::Failed { error } => domain::ExecutionResult::Failed {
                error: error.clone(),
            },
            ExecutionResult::Rejected { error } => domain::ExecutionResult::Rejected {
                error: error.clone(),
            },
        },
    }
}

pub(crate) type CoreDelivery = domain::Delivery<TestTask, Value, String>;

impl Envelope {
    pub(crate) fn to_core(&self) -> CoreDelivery {
        domain::Delivery::new(
            self.source_instance_id,
            self.target_instance_id,
            match &self.message {
                Message::SubmitOperation(value) => {
                    domain::Message::SubmitOperation(core_operation(value))
                }
                Message::DispatchAttempt(value) => {
                    domain::Message::DispatchAttempt(domain::DispatchAttempt {
                        attempt_id: value.attempt_id,
                        operation: core_operation(&value.operation),
                    })
                }
                Message::SubmitReport(value) => domain::Message::SubmitReport(core_report(value)),
            },
        )
    }

    pub(crate) fn from_core(value: &CoreDelivery) -> Self {
        Self::new(
            value.source_instance_id,
            value.target_instance_id,
            match &value.message {
                domain::Message::SubmitOperation(value) => Message::SubmitOperation(
                    SubmitOperation::new(value.operation_id, value.task.clone()),
                ),
                domain::Message::DispatchAttempt(value) => {
                    Message::DispatchAttempt(DispatchAttempt {
                        attempt_id: value.attempt_id,
                        operation: SubmitOperation::new(
                            value.operation.operation_id,
                            value.operation.task.clone(),
                        ),
                    })
                }
                domain::Message::SubmitReport(value) => Message::SubmitReport(SubmitReport {
                    report_id: value.report_id,
                    operation_id: value.operation_id,
                    attempt_id: value.attempt_id,
                    effect: match value.effect {
                        domain::Effect::None => Effect::None,
                        domain::Effect::Observed => Effect::Observed,
                        domain::Effect::Unknown => Effect::Unknown,
                    },
                    result: match &value.result {
                        domain::ExecutionResult::Succeeded { output } => {
                            ExecutionResult::Succeeded {
                                output: output.clone(),
                            }
                        }
                        domain::ExecutionResult::Failed { error } => ExecutionResult::Failed {
                            error: error.clone(),
                        },
                        domain::ExecutionResult::Rejected { error } => ExecutionResult::Rejected {
                            error: error.clone(),
                        },
                    },
                }),
            },
        )
    }
}

impl Limits {
    pub(crate) fn core(self) -> beamlet::memory::Limits {
        beamlet::memory::Limits {
            max_records: self.max_records,
            queue_capacity: self.queue_capacity,
            max_concurrency: self.max_concurrency,
        }
    }
}
