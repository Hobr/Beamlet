//! 独立 Authority 入口, 只接纳请求与收录证据, 不持有执行器

use crate::{
    Limits, OperationView, ReportDisposition, StateError, Submission,
    id::{AttemptId, NodeInstanceId, OperationId, ReportId},
    model::{Delivery, Message, Operation},
};
use beamlet::memory::Authority as Ledger;

/// Authority 的应用入口, 将请求接纳与消息交付分开
///
/// 返回授权不表示已经发送, 调用方负责交付并记录派发观察
/// 所有记录仅在内存中保留, 不提供可靠重投或重启恢复
#[derive(Debug)]
pub struct Authority<P, O, E> {
    instance: NodeInstanceId,
    ledger: Ledger<P, O, E>,
}

impl<P: Clone + Eq, O: Clone + Eq, E: Clone + Eq> Authority<P, O, E> {
    /// 使用静态 Work 实例列表创建独立 Authority
    ///
    /// # 错误
    /// 资源上限无效, Work 列表为空或实例身份重复时返回错误
    pub fn new(
        instance: NodeInstanceId,
        workers: Vec<NodeInstanceId>,
        limits: Limits,
    ) -> Result<Self, StateError> {
        Ok(Self {
            instance,
            ledger: Ledger::new(instance, workers, limits)?,
        })
    }

    /// 接纳本地应用请求并返回待交付授权, 不自动发送或接触 Work
    ///
    /// 重复提交只返回原有授权, 不表示应当自动重新交付
    ///
    /// # 错误
    /// 身份冲突或记录容量不足时返回错误, 不改变已保留事实
    pub fn submit(
        &mut self,
        operation: Operation<P>,
        attempt: AttemptId,
    ) -> Result<Submission<P, O, E>, StateError> {
        self.ledger.submit(
            Delivery::new(
                self.instance,
                self.instance,
                Message::SubmitOperation(operation),
            ),
            attempt,
        )
    }

    /// 调用方确认已发出后记录派发观察, 不代表 Work 已接纳
    ///
    /// # 错误
    /// 请求尚未被接纳时返回错误
    pub fn mark_dispatched(&mut self, operation: OperationId) -> Result<(), StateError> {
        self.ledger.mark_dispatched(operation)
    }

    /// 校验并保留收到的 Report, 不因等待超时而丢弃迟到证据
    ///
    /// # 错误
    /// 消息, 实例绑定, 身份, 证据或记录容量不合法时返回错误
    pub fn receive_report(
        &mut self,
        report: Delivery<P, O, E>,
    ) -> Result<ReportDisposition, StateError> {
        self.ledger.receive_report(report)
    }

    /// 查询请求的当前观察, 不访问 Work 的状态
    pub fn operation(&self, operation: OperationId) -> Option<&OperationView<P, O, E>> {
        self.ledger.operation(operation)
    }

    /// 查询已保留的证据, 包括未被采用为结果的 Report
    pub fn report(&self, report: ReportId) -> Option<&Delivery<P, O, E>> {
        self.ledger.report(report)
    }

    /// 只标记等待超时, 不取消执行或产生新授权
    ///
    /// # 错误
    /// 请求尚未被接纳时返回错误
    pub fn mark_wait_timeout(&mut self, operation: OperationId) -> Result<(), StateError> {
        self.ledger.mark_wait_timeout(operation)
    }
}
