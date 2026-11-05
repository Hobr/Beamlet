//! 原型测试的兼容导出; 实际实现位于 Agent 测试支持与 Kernel

pub use beamlet_agent::testing::protocol::{
    AttemptId, Constraints, DispatchAttempt, Effect, Envelope, ExecutionResult, Limits, Message,
    NodeInstanceId, OperationId, PROTOCOL_VERSION, ProtocolError, ReportId, SubmitOperation,
    SubmitReport, TestTask, Uuid, Value,
};
