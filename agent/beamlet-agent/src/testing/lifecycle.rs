//! 配置模式角色启动通知的严格 JSON Adapter, 不表示在线或授予执行权

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::protocol::ProtocolError;

/// 角色启动通知的公共订阅地址, 不接收 Client 生命周期公告
pub const SUBSCRIPTION: &str = "beamlet/v0/lifecycle/roles/*/*";
/// 单条公共启动通知的应用字节预算
pub const MAX_BYTES: usize = 4096;

/// 发布启动通知的业务角色, Client 不属于发布者
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum Role {
    /// 持有 Operation 并授予执行权
    Authority,
    /// 接纳 Attempt 并执行
    Worker,
}

impl std::fmt::Display for Role {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Authority => "Authority",
            Self::Worker => "Worker",
        })
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum Kind {
    RoleStarted,
}

/// 一次运行实例的启动事实, 周期重播必须保持内容不变
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RoleStarted {
    protocol_version: u16,
    kind: Kind,
    /// 发起公告的业务角色
    pub role: Role,
    /// 所属 Node 的逻辑身份, 未认证的自报元数据
    pub node_id: Uuid,
    /// 所属 Node 的本次运行身份
    pub node_instance_id: Uuid,
    /// Authority 或 Worker 的逻辑身份
    pub role_id: Uuid,
    /// Authority 或 Worker 的本次运行身份
    pub role_instance_id: Uuid,
}

impl RoleStarted {
    /// 为已启动的本地角色构造不可变通知, 不创建任何执行授权
    pub fn new(
        role: Role,
        node_id: Uuid,
        node_instance_id: Uuid,
        role_id: Uuid,
        role_instance_id: Uuid,
    ) -> Self {
        Self {
            protocol_version: 0,
            kind: Kind::RoleStarted,
            role,
            node_id,
            node_instance_id,
            role_id,
            role_instance_id,
        }
    }

    /// 绑定角色种类和运行实例的具体公共发布地址
    pub fn topic(&self) -> String {
        let role = match self.role {
            Role::Authority => "authority",
            Role::Worker => "worker",
        };
        format!(
            "beamlet/v0/lifecycle/roles/{role}/{}",
            self.role_instance_id.simple()
        )
    }

    /// 编码并检查整个通知的字节预算
    ///
    /// # 错误
    /// 版本, 大小或 JSON 编码不合法时返回错误
    pub fn to_json(&self) -> Result<Vec<u8>, ProtocolError> {
        self.validate()?;
        let bytes = serde_json::to_vec(self)?;
        if bytes.len() > MAX_BYTES {
            return Err(ProtocolError::MessageTooLarge);
        }
        Ok(bytes)
    }

    /// 在解码前检查字节预算, 严格验证字段, 角色和通知种类
    ///
    /// # 错误
    /// 超限, 版本或结构不合法时返回错误
    pub fn from_json(bytes: &[u8]) -> Result<Self, ProtocolError> {
        if bytes.len() > MAX_BYTES {
            return Err(ProtocolError::MessageTooLarge);
        }
        let notice: Self = serde_json::from_slice(bytes)?;
        notice.validate()?;
        Ok(notice)
    }

    fn validate(&self) -> Result<(), ProtocolError> {
        if self.protocol_version != 0 {
            return Err(ProtocolError::UnsupportedVersion(self.protocol_version));
        }
        Ok(())
    }
}
