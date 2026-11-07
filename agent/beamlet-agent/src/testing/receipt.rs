//! Report 收录回执的严格原型 Adapter, 不声明业务成功或持久化

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::protocol::{PROTOCOL_VERSION, ProtocolError};
use crate::{
    id::RoleInstanceId,
    model::{Delivery, Message},
};

/// 单条收录回执的应用字节上限
pub const MAX_BYTES: usize = 4096;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum Kind {
    ReportRetained,
}

/// 已校验并保留的 Report 身份绑定, 不表示已采用或已持久化
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ReportRetained {
    protocol_version: u16,
    kind: Kind,
    /// 收录证据的 Authority 运行实例
    pub source_instance_id: Uuid,
    /// 原证据的 Worker 运行实例
    pub target_instance_id: Uuid,
    /// 原 Operation 身份
    pub operation_id: Uuid,
    /// 原执行授权身份
    pub attempt_id: Uuid,
    /// 已保留的证据身份
    pub report_id: Uuid,
}

/// Worker 独立的收录回执收件箱, 不与 Attempt 混收
pub fn inbox(worker: RoleInstanceId) -> String {
    format!(
        "beamlet/v0/worker/{}/receipts",
        Uuid::from_u128(worker.as_u128()).simple()
    )
}

impl ReportRetained {
    /// 从原 Report 提取反向回执绑定, 调用方必须先收录再发送
    ///
    /// # 错误
    /// 原消息不是 Report 时返回错误
    pub fn for_report<P, O, E>(delivery: &Delivery<P, O, E>) -> Result<Self, ProtocolError> {
        let Message::SubmitReport(report) = &delivery.message else {
            return Err(ProtocolError::Json(serde::de::Error::custom(
                "回执只能绑定 Report",
            )));
        };
        Ok(Self {
            protocol_version: PROTOCOL_VERSION,
            kind: Kind::ReportRetained,
            source_instance_id: Uuid::from_u128(delivery.target_instance_id.as_u128()),
            target_instance_id: Uuid::from_u128(delivery.source_instance_id.as_u128()),
            operation_id: Uuid::from_u128(report.operation_id.as_u128()),
            attempt_id: Uuid::from_u128(report.attempt_id.as_u128()),
            report_id: Uuid::from_u128(report.report_id.as_u128()),
        })
    }

    /// 按原 Worker 运行实例生成具体发布地址
    pub fn topic(&self) -> String {
        inbox(self.target_instance_id.as_u128().into())
    }

    /// 编码有界回执, 不表示发送或远端收录
    ///
    /// # 错误
    /// 大小, 版本或 JSON 编码不合法时返回错误
    pub fn to_json(&self) -> Result<Vec<u8>, ProtocolError> {
        self.validate()?;
        let bytes = serde_json::to_vec(self)?;
        if bytes.len() > MAX_BYTES {
            return Err(ProtocolError::MessageTooLarge);
        }
        Ok(bytes)
    }

    /// 解码前检查上限, 拒绝未知字段和不支持的版本或种类
    ///
    /// # 错误
    /// 大小, 结构或版本不合法时返回错误
    pub fn from_json(bytes: &[u8]) -> Result<Self, ProtocolError> {
        if bytes.len() > MAX_BYTES {
            return Err(ProtocolError::MessageTooLarge);
        }
        let receipt: Self = serde_json::from_slice(bytes)?;
        receipt.validate()?;
        Ok(receipt)
    }

    fn validate(&self) -> Result<(), ProtocolError> {
        if self.protocol_version != PROTOCOL_VERSION {
            return Err(ProtocolError::UnsupportedVersion(self.protocol_version));
        }
        Ok(())
    }
}
