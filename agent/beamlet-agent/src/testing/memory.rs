//! v0 JSON 测试 Adapter: 校验传输数据并投影内存账本, 不实现领域状态机

use super::protocol::*;
use beamlet::memory as runtime;
/// 状态与接纳结论来自底层实现
pub use beamlet::memory::{Admission, OperationPhase, ReportDisposition, WaitStatus, WorkerPhase};
use std::collections::HashMap;
use thiserror::Error;

/// Authority 从保留的请求记录中提供的只读视图
#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub struct OperationView {
    /// 已固定的执行授权; 克隆它不会创建新的 Attempt
    pub dispatch: Envelope,
    /// Authority 最近一次已知的观察状态
    pub phase: OperationPhase,
    /// 等待超时不代表执行已经结束
    pub wait_status: WaitStatus,
    /// 本原型选作观察结果的第一份有效 Report
    pub adopted_report: Option<ReportId>,
}

/// 将客户端请求接纳到内存后的结果
#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub struct Submission {
    /// 区分首次接纳与重复请求查询
    pub admission: Admission,
    /// 原有执行授权, 包含保持不变的目标运行实例
    pub dispatch: Envelope,
}

/// 协议投影只负责格式校验; 身份与采用规则在底层 Authority 中执行
#[derive(Debug)]
pub struct Authority {
    inner: runtime::Authority<TestTask, Value, String>,
    limits: Limits,
    operations: HashMap<OperationId, OperationView>,
    reports: HashMap<ReportId, Envelope>,
}
impl Authority {
    /// 创建传输校验与只读投影
    ///
    /// # 错误
    /// 配置无效时返回错误
    pub fn new(
        instance: RoleInstanceId,
        workers: Vec<RoleInstanceId>,
        limits: Limits,
    ) -> Result<Self, StateError> {
        limits.validate()?;
        Ok(Self {
            inner: runtime::Authority::new(instance, workers, limits.core())?,
            limits,
            operations: HashMap::new(),
            reports: HashMap::new(),
        })
    }

    /// 入账前校验原请求及派发消息, 保持超限拒绝的原子性
    ///
    /// # 错误
    /// 格式, 身份或容量不合法时不改变任何底层记录
    pub fn submit(&mut self, envelope: Envelope, id: AttemptId) -> Result<Submission, StateError> {
        envelope.validate(&self.limits)?;
        let delivery = envelope.to_core();
        let preview = self.inner.preview_submit(&delivery, id)?;
        let dispatch = Envelope::from_core(&preview.dispatch);
        dispatch.validate(&self.limits)?;
        let accepted = self.inner.submit(delivery, id)?;
        let Message::DispatchAttempt(attempt) = &dispatch.message else {
            unreachable!("preview is an authorization");
        };
        self.refresh(attempt.operation.operation_id);
        Ok(Submission {
            admission: accepted.admission,
            dispatch,
        })
    }

    fn refresh(&mut self, id: OperationId) {
        if let Some(view) = self.inner.operation(id) {
            self.operations.insert(
                id,
                OperationView {
                    dispatch: Envelope::from_core(&view.dispatch),
                    phase: view.phase,
                    wait_status: view.wait_status,
                    adopted_report: view.adopted_report,
                },
            );
        }
    }

    /// 记录派发观察并刷新只读投影
    ///
    /// # 错误
    /// 请求不存在时返回错误
    pub fn mark_dispatched(&mut self, id: OperationId) -> Result<(), StateError> {
        self.inner.mark_dispatched(id)?;
        self.refresh(id);
        Ok(())
    }

    /// 只标记等待超时, 不触发取消或重新执行
    ///
    /// # 错误
    /// 请求不存在时返回错误
    pub fn mark_wait_timeout(&mut self, id: OperationId) -> Result<(), StateError> {
        self.inner.mark_wait_timeout(id)?;
        self.refresh(id);
        Ok(())
    }

    /// 校验并交由底层收录证据, 成功后更新格式投影
    ///
    /// # 错误
    /// 格式, 绑定, 身份或容量不合法时返回错误
    pub fn receive_report(&mut self, envelope: Envelope) -> Result<ReportDisposition, StateError> {
        envelope.validate(&self.limits)?;
        let disposition = self.inner.receive_report(envelope.to_core())?;
        let Message::SubmitReport(report) = &envelope.message else {
            unreachable!("accepted evidence is a report");
        };
        self.refresh(report.operation_id);
        self.reports.insert(report.report_id, envelope);
        Ok(disposition)
    }

    /// 返回协议格式的只读请求投影
    pub fn operation(&self, id: OperationId) -> Option<&OperationView> {
        self.operations.get(&id)
    }
    /// 返回已经通过底层校验的证据
    pub fn report(&self, id: ReportId) -> Option<&Envelope> {
        self.reports.get(&id)
    }
}

/// 对单个内存 Worker 进行协议校验, 不创建后台任务
#[derive(Debug)]
pub struct Worker {
    inner: runtime::Worker<TestTask, Value, String>,
    limits: Limits,
    reports: HashMap<AttemptId, Envelope>,
}
impl Worker {
    /// 创建受限协议投影
    ///
    /// # 错误
    /// 资源配置无效时返回错误
    pub fn new(
        instance: RoleInstanceId,
        authority: RoleInstanceId,
        limits: Limits,
    ) -> Result<Self, StateError> {
        limits.validate()?;
        Ok(Self {
            inner: runtime::Worker::new(instance, authority, limits.core())?,
            limits,
            reports: HashMap::new(),
        })
    }
    /// 校验格式后由底层执行接纳和去重
    ///
    /// # 错误
    /// 格式, 身份, 实例或容量不合法时返回错误
    pub fn accept(&mut self, envelope: Envelope) -> Result<WorkerPhase, StateError> {
        envelope.validate(&self.limits)?;
        Ok(self.inner.accept(envelope.to_core())?)
    }
    /// 显式取出一次授权, 不执行任务
    pub fn start_next(&mut self) -> Option<Envelope> {
        self.inner.start_next().as_ref().map(Envelope::from_core)
    }
    /// 交由底层校验并保存证据, 再刷新协议投影
    ///
    /// # 错误
    /// 格式, 绑定或阶段不合法时返回错误
    pub fn complete(&mut self, envelope: Envelope) -> Result<(), StateError> {
        envelope.validate(&self.limits)?;
        self.inner.complete(envelope.to_core())?;
        let Message::SubmitReport(report) = &envelope.message else {
            unreachable!("completed evidence is a report");
        };
        self.reports.insert(report.attempt_id, envelope);
        Ok(())
    }
    /// 查询底层推进阶段
    pub fn phase(&self, id: AttemptId) -> Option<WorkerPhase> {
        self.inner.phase(id)
    }
    /// 查询已经缓存的同一份协议证据
    pub fn report(&self, id: AttemptId) -> Option<&Envelope> {
        self.reports.get(&id)
    }
}

/// 内存原型的接纳与状态转换错误
#[derive(Debug, Error)]
#[non_exhaustive]
pub enum StateError {
    /// 消息在修改状态前未通过传输格式校验
    #[error(transparent)]
    Protocol(#[from] ProtocolError),
    /// 静态 Worker 配置为空, 或存在重复的实例身份
    #[error("workers must be nonempty and unique")]
    InvalidWorkers,
    /// 消息的目标是另一个进程运行实例
    #[error("message targets a different node incarnation")]
    WrongTarget,
    /// 当前状态转换不接收此消息类型
    #[error("unexpected message kind")]
    WrongMessage,
    /// 发送方不是配置的 Authority 运行实例
    #[error("sender is not the configured authority")]
    UntrustedAuthority,
    /// 该 Operation 身份已经绑定到不同的定义
    #[error("operation identity conflicts with retained definition")]
    OperationConflict,
    /// 同一 Attempt 身份被用于不同的绑定或请求
    #[error("attempt identity conflicts with retained authorization")]
    AttemptConflict,
    /// 同一 Report 身份被用于不同的证据
    #[error("report identity conflicts with retained evidence")]
    ReportConflict,
    /// 证据与保留的 Operation, Attempt 或节点绑定不匹配
    #[error("evidence does not match the retained authorization")]
    InvalidBinding,
    /// 身份记录表已满; 不会淘汰已有记录
    #[error("retained identity capacity is exhausted")]
    Capacity,
    /// 等待队列已满, 本次新交付未被接纳
    #[error("worker queue is full")]
    QueueFull,
    /// 不存在具有此身份的已接纳请求
    #[error("operation is not retained")]
    UnknownOperation,
    /// 当前 Worker 阶段不允许提交此完成结果
    #[error("completion does not match the current worker phase")]
    InvalidTransition,
}

impl From<runtime::StateError> for StateError {
    fn from(error: runtime::StateError) -> Self {
        use beamlet::state::RuleError;
        match error {
            runtime::StateError::InvalidLimits => Self::Protocol(ProtocolError::InvalidLimits),
            runtime::StateError::Rule(RuleError::InvalidRejectionEffect) => {
                Self::Protocol(ProtocolError::InvalidRejectionEffect)
            }
            runtime::StateError::Rule(RuleError::InvalidTransition) => Self::InvalidTransition,
            runtime::StateError::InvalidWorkers => Self::InvalidWorkers,
            runtime::StateError::WrongTarget => Self::WrongTarget,
            runtime::StateError::WrongMessage => Self::WrongMessage,
            runtime::StateError::UntrustedAuthority => Self::UntrustedAuthority,
            runtime::StateError::OperationConflict => Self::OperationConflict,
            runtime::StateError::AttemptConflict => Self::AttemptConflict,
            runtime::StateError::ReportConflict => Self::ReportConflict,
            runtime::StateError::InvalidBinding => Self::InvalidBinding,
            runtime::StateError::Capacity => Self::Capacity,
            runtime::StateError::QueueFull => Self::QueueFull,
            runtime::StateError::UnknownOperation => Self::UnknownOperation,
            runtime::StateError::InvalidTransition => Self::InvalidTransition,
        }
    }
}
