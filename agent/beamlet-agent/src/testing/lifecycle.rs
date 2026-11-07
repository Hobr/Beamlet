//! 配置模式角色生命周期通知的严格 JSON Adapter, 不表示在线或授予执行权

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::protocol::ProtocolError;

/// 角色生命周期通知的公共订阅地址, 不接收 Client 生命周期公告
pub const SUBSCRIPTION: &str = "beamlet/v0/lifecycle/roles/*/*";
/// 单条公共生命周期通知的应用字节预算
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
    RoleExited,
}

/// 本地角色驱动退出时的排空观察, 不描述业务结果或外部效果
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum ExitOutcome {
    /// 本地角色正常完成 Draining, 不保证远端收录
    Drained,
    /// 排空或交付未确认, 不推断执行停止或无效果
    Unconfirmed,
}

impl std::fmt::Display for ExitOutcome {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Drained => "正常排空",
            Self::Unconfirmed => "排空或交付未确认",
        })
    }
}

/// 一次运行实例的启动或退出事实, 退出后迟到启动不能恢复活动状态
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RoleNotice {
    protocol_version: u16,
    kind: Kind,
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "present_outcome"
    )]
    outcome: Option<ExitOutcome>,
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

fn present_outcome<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<ExitOutcome>, D::Error> {
    ExitOutcome::deserialize(deserializer).map(Some)
}

impl RoleNotice {
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
            outcome: None,
            role,
            node_id,
            node_instance_id,
            role_id,
            role_instance_id,
        }
    }

    /// 从同一角色绑定构造退出事实, 不生成业务 Report
    pub fn exited(&self, outcome: ExitOutcome) -> Self {
        Self {
            kind: Kind::RoleExited,
            outcome: Some(outcome),
            ..self.clone()
        }
    }

    /// 退出结果为空表示启动事实, 不等于当前在线
    pub fn exit_outcome(&self) -> Option<ExitOutcome> {
        self.outcome
    }

    /// 比较角色和 Node 的完整绑定, 不比较生命周期阶段
    pub fn same_binding(&self, other: &Self) -> bool {
        self.role == other.role
            && self.node_id == other.node_id
            && self.node_instance_id == other.node_instance_id
            && self.role_id == other.role_id
            && self.role_instance_id == other.role_instance_id
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
        if !matches!(
            (self.kind, self.outcome),
            (Kind::RoleStarted, None) | (Kind::RoleExited, Some(_))
        ) {
            return Err(ProtocolError::Json(serde::de::Error::custom(
                "角色退出通知必须携带 outcome, 启动通知不能携带 outcome",
            )));
        }
        Ok(())
    }
}
