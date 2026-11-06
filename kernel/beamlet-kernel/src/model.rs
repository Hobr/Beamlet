//! 与编码, 任务种类和运行时无关的执行领域对象

use crate::{
    id::{AttemptId, OperationId, ReportId, RoleInstanceId},
    state::RuleError,
};

/// 不可变逻辑请求; 输入的具体类型由调用方选择
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Operation<P> {
    /// 稳定请求身份
    pub operation_id: OperationId,
    /// 不透明的请求定义, 不要求 JSON 或特定任务枚举
    pub task: P,
}

/// 一次执行授权; 重复交付沿用此身份与定义
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DispatchAttempt<P> {
    /// 执行授权身份
    pub attempt_id: AttemptId,
    /// 原始不可变请求
    pub operation: Operation<P>,
}

/// 效果证据的三个互斥结论, 不由执行成功或失败推导
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Effect {
    /// 证据确认没有外部效果
    None,
    /// 已观察到效果, 不承诺完整或仅发生一次
    Observed,
    /// 现有证据无法确定是否产生效果
    Unknown,
}

/// 互斥的完成结果; 输出与错误类型由外层决定
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ExecutionResult<O, E> {
    /// 执行返回输出
    Succeeded {
        /// 执行输出, 不代表 Authority 的采用决定
        output: O,
    },
    /// 执行失败, 但不能据此推断无效果
    Failed {
        /// 错误证据
        error: E,
    },
    /// 执行开始前被明确拒绝
    Rejected {
        /// 拒绝原因
        error: E,
    },
}

/// 与一次授权关联的证据, 不等于业务成功或采用决定
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SubmitReport<O, E> {
    /// 证据身份
    pub report_id: ReportId,
    /// 所属请求
    pub operation_id: OperationId,
    /// 所属执行授权
    pub attempt_id: AttemptId,
    /// 独立的效果证据
    pub effect: Effect,
    /// 执行结果
    pub result: ExecutionResult<O, E>,
}

impl<O, E> SubmitReport<O, E> {
    /// 校验执行前拒绝不能声称可能已产生效果
    ///
    /// # 错误
    /// 拒绝结果带有非空效果证据时返回错误
    pub fn validate(&self) -> Result<(), RuleError> {
        if matches!(self.result, ExecutionResult::Rejected { .. }) && self.effect != Effect::None {
            return Err(RuleError::InvalidRejectionEffect);
        }
        Ok(())
    }
}

/// 领域输入, 不包含协议版本, 编码, 传输 ACK 或网络地址
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Message<P, O, E> {
    /// 接纳逻辑请求
    SubmitOperation(Operation<P>),
    /// 交付执行授权
    DispatchAttempt(DispatchAttempt<P>),
    /// 收录执行证据
    SubmitReport(SubmitReport<O, E>),
}

/// 一次领域交付的实例绑定; 它不是序列化消息信封, 也不构成认证
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Delivery<P, O, E> {
    /// 交付来源实例
    pub source_instance_id: RoleInstanceId,
    /// 交付目标实例
    pub target_instance_id: RoleInstanceId,
    /// 已脱离传输格式的领域输入
    pub message: Message<P, O, E>,
}

impl<P, O, E> Delivery<P, O, E> {
    /// 关联实例身份与领域输入, 不执行传输或认证
    pub fn new(source: RoleInstanceId, target: RoleInstanceId, message: Message<P, O, E>) -> Self {
        Self {
            source_instance_id: source,
            target_instance_id: target,
            message,
        }
    }

    /// 只校验领域证据, 不读取编码, 时钟或外部状态
    ///
    /// # 错误
    /// 报告的效果与拒绝结论矛盾时返回错误
    pub fn validate(&self) -> Result<(), RuleError> {
        if let Message::SubmitReport(report) = &self.message {
            report.validate()?;
        }
        Ok(())
    }
}
