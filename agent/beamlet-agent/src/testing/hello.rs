//! 固定 Hello 演示的 Console 请求与结果编码, 不是通用 Agent 或传输契约

use super::protocol::{
    self, Envelope, ExecutionResult, Limits, Message, ProtocolError, SubmitReport, Uuid, Value,
};
use crate::{id::OperationId, model};
use serde::{Deserialize, Serialize, de::DeserializeOwned};

/// 固定演示任务, 不建立能力声明或动态注册表
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum Task {
    /// 执行直接传入的 Hello 函数
    Hello,
}

/// Console 向当前连接的 Node 提交的不可变请求, 不绑定未来重启的实例
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Request {
    protocol_version: u16,
    operation_id: Uuid,
    task: Task,
}

impl Request {
    /// 构造固定 Hello 请求; 重复提交必须复用原有身份
    pub fn hello(operation_id: Uuid) -> Self {
        Self {
            protocol_version: protocol::PROTOCOL_VERSION,
            operation_id,
            task: Task::Hello,
        }
    }

    /// 返回独立于 Console 路由身份的逻辑请求身份
    pub fn operation_id(&self) -> OperationId {
        self.operation_id.as_u128().into()
    }

    /// 去除编码字段, 生成不依赖 JSON 的领域请求
    pub fn operation(&self) -> model::Operation<Task> {
        model::Operation {
            operation_id: self.operation_id(),
            task: self.task,
        }
    }

    /// 编码为受限 JSON 请求
    ///
    /// # 错误
    /// 上限, 版本, 大小或 JSON 编码无效时返回错误
    pub fn to_json(&self, limits: &Limits) -> Result<Vec<u8>, ProtocolError> {
        check_version(self.protocol_version)?;
        encode(self, limits)
    }

    /// 在接纳前检查字节上限, 严格字段与版本
    ///
    /// # 错误
    /// 超限, 未知字段, 非 Hello 任务或不支持的版本会被拒绝
    pub fn from_json(bytes: &[u8], limits: &Limits) -> Result<Self, ProtocolError> {
        let request: Self = decode(bytes, limits)?;
        check_version(request.protocol_version)?;
        Ok(request)
    }
}

/// 固定 Hello 的跨进程授权编码, 不携带任意执行函数或 Console 回复地址
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Dispatch {
    protocol_version: u16,
    source_instance_id: Uuid,
    target_instance_id: Uuid,
    attempt_id: Uuid,
    operation: Request,
}

impl Dispatch {
    /// 编码已有授权, 不创建新的 Attempt 或选择其他 Worker
    ///
    /// # 错误
    /// 领域消息不是 DispatchAttempt 时返回错误
    pub fn from_delivery(
        delivery: &model::Delivery<Task, String, String>,
    ) -> Result<Self, ProtocolError> {
        let model::Message::DispatchAttempt(attempt) = &delivery.message else {
            return Err(invalid_message("预期为执行授权"));
        };
        Ok(Self {
            protocol_version: protocol::PROTOCOL_VERSION,
            source_instance_id: Uuid::from_u128(delivery.source_instance_id.as_u128()),
            target_instance_id: Uuid::from_u128(delivery.target_instance_id.as_u128()),
            attempt_id: Uuid::from_u128(attempt.attempt_id.as_u128()),
            operation: Request {
                protocol_version: protocol::PROTOCOL_VERSION,
                operation_id: Uuid::from_u128(attempt.operation.operation_id.as_u128()),
                task: attempt.operation.task,
            },
        })
    }

    /// 还原原始实例绑定及授权, Worker 仍须独立检查接纳规则
    pub fn delivery(&self) -> model::Delivery<Task, String, String> {
        model::Delivery::new(
            self.source_instance_id.as_u128().into(),
            self.target_instance_id.as_u128().into(),
            model::Message::DispatchAttempt(model::DispatchAttempt {
                attempt_id: self.attempt_id.as_u128().into(),
                operation: self.operation.operation(),
            }),
        )
    }

    /// 编码并检查完整授权的字节预算
    ///
    /// # 错误
    /// 版本, 上限, 大小或 JSON 编码无效时返回错误
    pub fn to_json(&self, limits: &Limits) -> Result<Vec<u8>, ProtocolError> {
        check_version(self.protocol_version)?;
        check_version(self.operation.protocol_version)?;
        encode(self, limits)
    }

    /// 在 Worker 接纳前检查字节预算, 严格字段与版本
    ///
    /// # 错误
    /// 未知字段, 非 Hello 任务, 错误版本或消息超限时返回错误
    pub fn from_json(bytes: &[u8], limits: &Limits) -> Result<Self, ProtocolError> {
        let dispatch: Self = decode(bytes, limits)?;
        check_version(dispatch.protocol_version)?;
        check_version(dispatch.operation.protocol_version)?;
        Ok(dispatch)
    }
}

/// 将 Worker 已缓存的 Report 编码为原有 v0 信封, 不表示 Authority 已收录
///
/// # 错误
/// 消息种类, 证据内容, 上限或 JSON 编码无效时返回错误
pub fn encode_report(
    delivery: &model::Delivery<Task, String, String>,
    limits: &Limits,
) -> Result<Vec<u8>, ProtocolError> {
    let model::Message::SubmitReport(report) = &delivery.message else {
        return Err(invalid_message("预期为执行报告"));
    };
    let response = Response::report(
        report,
        delivery.source_instance_id,
        delivery.target_instance_id,
    );
    let ResponseMessage::Report(envelope) = response.message else {
        return Err(invalid_message("预期为执行报告信封"));
    };
    envelope.to_json(limits)
}

/// 解码原有 v0 Report, 将 Hello 的字符串结果显式还原为领域数据
///
/// # 错误
/// 非 Report, 非字符串输出, 非法证据或有界协议检查失败时返回错误
pub fn decode_report(
    bytes: &[u8],
    limits: &Limits,
) -> Result<model::Delivery<Task, String, String>, ProtocolError> {
    let envelope = Envelope::from_json(bytes, limits)?;
    let Message::SubmitReport(report) = envelope.message else {
        return Err(invalid_message("预期为执行报告信封"));
    };
    let effect = match report.effect {
        protocol::Effect::None => model::Effect::None,
        protocol::Effect::Observed => model::Effect::Observed,
        protocol::Effect::Unknown => model::Effect::Unknown,
    };
    let result = match report.result {
        ExecutionResult::Succeeded {
            output: Value::String(output),
        } => model::ExecutionResult::Succeeded { output },
        ExecutionResult::Succeeded { .. } => {
            return Err(invalid_message("hello 输出必须是字符串"));
        }
        ExecutionResult::Failed { error } => model::ExecutionResult::Failed { error },
        ExecutionResult::Rejected { error } => model::ExecutionResult::Rejected { error },
    };
    Ok(model::Delivery::new(
        envelope.source_instance_id,
        envelope.target_instance_id,
        model::Message::SubmitReport(model::SubmitReport {
            report_id: report.report_id,
            operation_id: report.operation_id,
            attempt_id: report.attempt_id,
            effect,
            result,
        }),
    ))
}

fn invalid_message(message: &str) -> ProtocolError {
    ProtocolError::Json(serde::de::Error::custom(message))
}

/// 提交观察或已收录的 Report, 不把交付错误伪装成执行失败
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(
    tag = "kind",
    content = "body",
    rename_all = "snake_case",
    deny_unknown_fields
)]
#[non_exhaustive]
pub enum ResponseMessage {
    /// 已由 Authority 保留的证据, 保留原始实例与授权绑定
    Report(Envelope),
    /// 原有请求仍被保留, 当前没有可返回的证据; 不自动重新授权
    Pending {
        /// 查询的原有请求身份
        operation_id: Uuid,
    },
    /// 提交调用返回错误, 不据此推断请求未被接纳或执行没有效果
    SubmissionError {
        /// 本次提交的请求身份
        operation_id: Uuid,
        /// 错误与当前保留状态的演示文本, 不是失败 Report
        error: String,
    },
}

/// Console 结果包装, 内层 Report 继续使用现有 v0 编码
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Response {
    protocol_version: u16,
    message: ResponseMessage,
}

impl Response {
    /// 包装提交观察; 不创建新的执行证据
    pub fn new(message: ResponseMessage) -> Self {
        Self {
            protocol_version: protocol::PROTOCOL_VERSION,
            message,
        }
    }

    /// 将已收录的领域 Report 转为现有的字节协议表示
    pub fn report(
        report: &model::SubmitReport<String, String>,
        worker: crate::id::RoleInstanceId,
        authority: crate::id::RoleInstanceId,
    ) -> Self {
        let report = SubmitReport {
            report_id: report.report_id,
            operation_id: report.operation_id,
            attempt_id: report.attempt_id,
            effect: match report.effect {
                model::Effect::None => protocol::Effect::None,
                model::Effect::Observed => protocol::Effect::Observed,
                model::Effect::Unknown => protocol::Effect::Unknown,
            },
            result: match &report.result {
                model::ExecutionResult::Succeeded { output } => ExecutionResult::Succeeded {
                    output: Value::String(output.clone()),
                },
                model::ExecutionResult::Failed { error } => ExecutionResult::Failed {
                    error: error.clone(),
                },
                model::ExecutionResult::Rejected { error } => ExecutionResult::Rejected {
                    error: error.clone(),
                },
            },
        };
        Self::new(ResponseMessage::Report(Envelope::new(
            worker,
            authority,
            Message::SubmitReport(report),
        )))
    }

    /// 返回已通过编码校验的响应内容
    pub fn message(&self) -> &ResponseMessage {
        &self.message
    }

    /// 编码并校验整个包装的字节预算, 不只校验内层 Report
    ///
    /// # 错误
    /// 版本, 证据内容, 大小或 JSON 编码无效时返回错误
    pub fn to_json(&self, limits: &Limits) -> Result<Vec<u8>, ProtocolError> {
        self.validate(limits)?;
        encode(self, limits)
    }

    /// 解析有界响应并检查内层 Report 的约束
    ///
    /// # 错误
    /// 未知字段, 错误版本, 非法证据或消息超限时返回错误
    pub fn from_json(bytes: &[u8], limits: &Limits) -> Result<Self, ProtocolError> {
        let response: Self = decode(bytes, limits)?;
        response.validate(limits)?;
        Ok(response)
    }

    fn validate(&self, limits: &Limits) -> Result<(), ProtocolError> {
        check_version(self.protocol_version)?;
        if let ResponseMessage::Report(report) = &self.message {
            report.validate(limits)?;
            if !matches!(report.message, Message::SubmitReport(_)) {
                return Err(ProtocolError::Json(serde::de::Error::custom(
                    "hello 响应必须包含执行报告",
                )));
            }
        }
        Ok(())
    }
}

fn check_version(version: u16) -> Result<(), ProtocolError> {
    if version != protocol::PROTOCOL_VERSION {
        return Err(ProtocolError::UnsupportedVersion(version));
    }
    Ok(())
}

fn encode<T: Serialize>(value: &T, limits: &Limits) -> Result<Vec<u8>, ProtocolError> {
    limits.validate()?;
    let bytes = serde_json::to_vec(value)?;
    if bytes.len() > limits.max_message_bytes {
        return Err(ProtocolError::MessageTooLarge);
    }
    Ok(bytes)
}

fn decode<T: DeserializeOwned>(bytes: &[u8], limits: &Limits) -> Result<T, ProtocolError> {
    limits.validate()?;
    if bytes.len() > limits.max_message_bytes {
        return Err(ProtocolError::MessageTooLarge);
    }
    Ok(serde_json::from_slice(bytes)?)
}
