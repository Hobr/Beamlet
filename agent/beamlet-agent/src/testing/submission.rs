//! Client 提交及接纳关联协议, 与执行授权的 Operation 编码分开
use super::{
    hello::{Response, ResponseMessage, Task},
    protocol::{Limits, Message, PROTOCOL_VERSION, ProtocolError},
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Client 重投时必须保持同一 key 和完整定义
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct Submission {
    protocol_version: u16,
    pub submission_key: Uuid,
    pub task: Task,
}
impl Submission {
    /// 构造固定任务提交, 不分配 OperationId
    pub fn hello(submission_key: Uuid) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            submission_key,
            task: Task::Hello,
        }
    }
    /// Authority 分配身份后还原内部不可变请求
    pub fn operation(&self, id: Uuid) -> crate::model::Operation<Task> {
        crate::model::Operation {
            operation_id: id.as_u128().into(),
            task: self.task,
        }
    }
    /// 有界编码
    /// # 错误
    /// JSON 或协议校验失败时返回错误
    pub fn to_json(&self, limits: &Limits) -> Result<Vec<u8>, ProtocolError> {
        check(self.protocol_version)?;
        encode(self, limits)
    }
    /// 严格有界解码
    /// # 错误
    /// JSON, 版本或大小不合法时返回错误
    pub fn from_json(bytes: &[u8], limits: &Limits) -> Result<Self, ProtocolError> {
        let value: Self = decode(bytes, limits)?;
        check(value.protocol_version)?;
        Ok(value)
    }
}
/// 接纳映射随每一份结果返回, 允许 Report 先于接纳回执到达
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SubmissionReply {
    protocol_version: u16,
    pub submission_key: Uuid,
    pub authority_instance_id: Uuid,
    pub operation_id: Option<Uuid>,
    pub attempt_id: Option<Uuid>,
    pub response: Option<Response>,
    pub error: Option<String>,
}
impl SubmissionReply {
    /// 已成功接纳的原映射, 不代表已执行
    pub fn accepted(key: Uuid, authority: Uuid, operation: Uuid, attempt: Uuid) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            submission_key: key,
            authority_instance_id: authority,
            operation_id: Some(operation),
            attempt_id: Some(attempt),
            response: None,
            error: None,
        }
    }
    /// 未接纳的提交错误, 不创建业务身份或 Report
    pub fn rejected(key: Uuid, authority: Uuid, error: String) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION,
            submission_key: key,
            authority_instance_id: authority,
            operation_id: None,
            attempt_id: None,
            response: None,
            error: Some(error),
        }
    }
    /// 在原接纳映射中携带后续观察
    pub fn with_response(&self, response: Response) -> Self {
        Self {
            response: Some(response),
            ..self.clone()
        }
    }
    /// 编码并校验完整身份关联
    /// # 错误
    /// 结构或关联非法时返回错误
    pub fn to_json(&self, limits: &Limits) -> Result<Vec<u8>, ProtocolError> {
        self.validate(limits)?;
        encode(self, limits)
    }
    /// 严格解码并校验完整身份关联
    /// # 错误
    /// 大小, JSON 或关联非法时返回错误
    pub fn from_json(bytes: &[u8], limits: &Limits) -> Result<Self, ProtocolError> {
        let value: Self = decode(bytes, limits)?;
        value.validate(limits)?;
        Ok(value)
    }
    fn validate(&self, limits: &Limits) -> Result<(), ProtocolError> {
        check(self.protocol_version)?;
        if self.error.is_some() {
            if self.operation_id.is_some() || self.attempt_id.is_some() || self.response.is_some() {
                return Err(invalid());
            }
            return Ok(());
        }
        let (Some(op), Some(attempt)) = (self.operation_id, self.attempt_id) else {
            return Err(invalid());
        };
        if let Some(response) = &self.response {
            response.to_json(limits)?;
            match response.message() {
                ResponseMessage::Report(envelope) => {
                    let Message::SubmitReport(report) = &envelope.message else {
                        return Err(invalid());
                    };
                    if report.operation_id.as_u128() != op.as_u128()
                        || report.attempt_id.as_u128() != attempt.as_u128()
                        || envelope.target_instance_id.as_u128()
                            != self.authority_instance_id.as_u128()
                    {
                        return Err(invalid());
                    }
                }
                ResponseMessage::Pending { operation_id }
                | ResponseMessage::SubmissionError { operation_id, .. } => {
                    if *operation_id != op {
                        return Err(invalid());
                    }
                }
            }
        }
        Ok(())
    }
}
fn invalid() -> ProtocolError {
    ProtocolError::Json(serde::de::Error::custom("提交回复身份关联或结构不合法"))
}
fn check(version: u16) -> Result<(), ProtocolError> {
    if version != PROTOCOL_VERSION {
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
fn decode<T: serde::de::DeserializeOwned>(
    bytes: &[u8],
    limits: &Limits,
) -> Result<T, ProtocolError> {
    limits.validate()?;
    if bytes.len() > limits.max_message_bytes {
        return Err(ProtocolError::MessageTooLarge);
    }
    Ok(serde_json::from_slice(bytes)?)
}
