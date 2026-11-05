//! 不访问存储, 时钟或运行时的领域状态规则

use crate::model::ExecutionResult;
use thiserror::Error;

/// Authority 的观察状态; 已派发不代表 Work 已经开始执行
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum OperationPhase {
    /// 请求及其一次执行授权已保存在内存中
    Accepted,
    /// 调用方已记录尝试派发的事实
    Dispatched,
    /// 至少已保留一份与授权绑定的 Report
    Reported,
}

/// 本地等待状态, 与执行情况和证据相互独立
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum WaitStatus {
    /// 调用方尚未报告等待超时
    Waiting,
    /// 等待已超时, 但执行仍可能产生证据
    TimedOut,
}

/// Work 的推进状态, 不承诺持久接纳, 也不证明实际执行情况
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum WorkPhase {
    /// Attempt 正在有界队列中等待
    Queued,
    /// 调用方已取走 Attempt, 准备在本模块之外执行
    Running,
    /// 结果已保留, 重复交付时可以返回该结果
    Completed,
}

impl WorkPhase {
    /// 根据当前阶段与结果决定是否允许完成, 不修改任何存储
    ///
    /// # 错误
    /// 排队任务声称已执行, 运行任务声称执行前拒绝, 或重复改变已完成结果时返回错误
    pub fn finish<O, E>(self, result: &ExecutionResult<O, E>) -> Result<Self, RuleError> {
        let rejected = matches!(result, ExecutionResult::Rejected { .. });
        match (self, rejected) {
            (Self::Queued, true) | (Self::Running, false) => Ok(Self::Completed),
            _ => Err(RuleError::InvalidTransition),
        }
    }
}

/// 领域规则错误, 不包含协议或运行时错误
#[derive(Clone, Copy, Debug, Eq, Error, PartialEq)]
pub enum RuleError {
    /// 执行前拒绝不能附带可能存在的外部效果
    #[error("a rejected execution must have no effects")]
    InvalidRejectionEffect,
    /// 当前阶段不允许此结果
    #[error("illegal work transition")]
    InvalidTransition,
}
