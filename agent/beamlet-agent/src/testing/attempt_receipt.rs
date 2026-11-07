//! Attempt 接纳回执的严格原型 Adapter, 不证明执行开始或完成

use super::protocol::{PROTOCOL_VERSION, ProtocolError};
use super::receipt::MAX_BYTES;
use crate::{
    id::RoleInstanceId,
    model::{Delivery, Message},
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum Kind {
    AttemptAccepted,
}

/// Worker 已接纳的原授权身份, 不表示开始执行或持久化
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct AttemptAccepted {
    protocol_version: u16,
    kind: Kind,
    /// 接纳授权的 Worker 运行实例
    pub source_instance_id: Uuid,
    /// 签发授权的 Authority 运行实例
    pub target_instance_id: Uuid,
    /// 原请求身份
    pub operation_id: Uuid,
    /// 原授权身份
    pub attempt_id: Uuid,
}

/// Authority 独立接纳回执收件箱
pub fn inbox(authority: RoleInstanceId) -> String {
    format!(
        "beamlet/v0/authority/{}/receipts",
        Uuid::from_u128(authority.as_u128()).simple()
    )
}

impl AttemptAccepted {
    /// 提取原授权的反向绑定, 调用方必须先成功接纳
    ///
    /// # 错误
    /// 消息不是授权时返回错误
    pub fn for_dispatch<P, O, E>(delivery: &Delivery<P, O, E>) -> Result<Self, ProtocolError> {
        let Message::DispatchAttempt(attempt) = &delivery.message else {
            return Err(ProtocolError::Json(serde::de::Error::custom(
                "回执必须绑定 Attempt",
            )));
        };
        Ok(Self {
            protocol_version: PROTOCOL_VERSION,
            kind: Kind::AttemptAccepted,
            source_instance_id: Uuid::from_u128(delivery.target_instance_id.as_u128()),
            target_instance_id: Uuid::from_u128(delivery.source_instance_id.as_u128()),
            operation_id: Uuid::from_u128(attempt.operation.operation_id.as_u128()),
            attempt_id: Uuid::from_u128(attempt.attempt_id.as_u128()),
        })
    }
    /// 原 Authority 运行实例的回执地址
    pub fn topic(&self) -> String {
        inbox(self.target_instance_id.as_u128().into())
    }
    /// 编码有界回执
    ///
    /// # 错误
    /// 版本或大小不合法时返回错误
    pub fn to_json(&self) -> Result<Vec<u8>, ProtocolError> {
        self.validate()?;
        let bytes = serde_json::to_vec(self)?;
        if bytes.len() > MAX_BYTES {
            return Err(ProtocolError::MessageTooLarge);
        }
        Ok(bytes)
    }
    /// 严格解码回执, 不接受未知字段
    ///
    /// # 错误
    /// JSON, 版本或大小不合法时返回错误
    pub fn from_json(bytes: &[u8]) -> Result<Self, ProtocolError> {
        if bytes.len() > MAX_BYTES {
            return Err(ProtocolError::MessageTooLarge);
        }
        let value: Self = serde_json::from_slice(bytes)?;
        value.validate()?;
        Ok(value)
    }
    fn validate(&self) -> Result<(), ProtocolError> {
        if self.protocol_version != PROTOCOL_VERSION {
            return Err(ProtocolError::UnsupportedVersion(self.protocol_version));
        }
        Ok(())
    }
}
