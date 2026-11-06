//! 调用方提供的领域身份, 不生成随机数, 不依赖序列化库

use std::fmt;

macro_rules! identity {
    ($name:ident, $description:literal) => {
        #[doc = $description]
        #[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
        pub struct $name(u128);

        impl $name {
            /// 从调用方提供的 128 位值构造身份, 不创建新的执行授权
            pub const fn from_u128(value: u128) -> Self {
                Self(value)
            }
            /// 返回原始 128 位值, 编码格式由外层决定
            pub const fn as_u128(self) -> u128 {
                self.0
            }
        }

        impl From<u128> for $name {
            fn from(value: u128) -> Self {
                Self(value)
            }
        }

        impl From<$name> for u128 {
            fn from(value: $name) -> Self {
                value.0
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                write!(
                    f,
                    "{:08x}-{:04x}-{:04x}-{:04x}-{:012x}",
                    self.0 >> 96,
                    (self.0 >> 80) & 0xffff,
                    (self.0 >> 64) & 0xffff,
                    (self.0 >> 48) & 0xffff,
                    self.0 & 0xffffffffffff
                )
            }
        }
    };
}

identity!(OperationId, "标识不可变逻辑请求; 身份不由输入内容决定.");
identity!(AttemptId, "标识一次执行授权, 而非一次消息交付.");
identity!(ReportId, "标识执行证据, 与证据是否被采用无关.");
identity!(NodeId, "标识 Node 的稳定逻辑身份, 不表示运行实例.");
identity!(NodeInstanceId, "标识 Node 的一次运行, 不用于角色交付绑定.");
identity!(AuthorityId, "标识 Authority 的稳定逻辑身份.");
identity!(WorkerId, "标识 Worker 的稳定逻辑身份.");
identity!(AuthorityInstanceId, "标识 Authority 的一次运行.");
identity!(WorkerInstanceId, "标识 Worker 的一次运行.");
identity!(
    RoleInstanceId,
    "标识领域交付绑定的角色运行实例, 不等于 Node 运行身份."
);

impl From<AuthorityInstanceId> for RoleInstanceId {
    fn from(value: AuthorityInstanceId) -> Self {
        Self::from_u128(value.as_u128())
    }
}

impl From<WorkerInstanceId> for RoleInstanceId {
    fn from(value: WorkerInstanceId) -> Self {
        Self::from_u128(value.as_u128())
    }
}
