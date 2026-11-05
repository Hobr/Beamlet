//! 应用执行入口: 关联意图, 派发授权并收录完成证据, 不实现自主 Agent Loop

use beamlet::{executor::Executor, memory::Authority};
use std::future::Future;
use thiserror::Error;

/// 应用只依赖本 crate 即可配置, 提交和查询, 不需要直接导入底层 crate
pub use beamlet::{
    executor::ExecutorError,
    id,
    memory::{
        Admission, Limits, OperationPhase, OperationView, StateError, Submission, WaitStatus,
    },
    model, state,
};
use id::{AttemptId, NodeInstanceId, OperationId, ReportId};
use model::{Delivery, DispatchAttempt, Message, Operation, SubmitReport};

/// 调用方显式推进的内存执行用例, 隐藏 Authority 与 Work 的组装循环
#[derive(Debug)]
pub struct Agent<P, O, E> {
    instance: NodeInstanceId,
    authority: Authority<P, O, E>,
    executor: Executor<P, O, E>,
}

impl<P, O, E> Agent<P, O, E>
where
    P: Clone + Eq + Send + 'static,
    O: Clone + Eq + Send + 'static,
    E: Clone + Eq + Send + 'static,
{
    /// 以静态 Work 实例和独立资源上限创建应用入口
    ///
    /// # 错误
    /// 实例配置或资源上限无效时返回错误
    pub fn new(
        instance: NodeInstanceId,
        workers: Vec<NodeInstanceId>,
        limits: Limits,
    ) -> Result<Self, AgentError> {
        Ok(Self {
            instance,
            authority: Authority::new(instance, workers.clone(), limits)?,
            executor: Executor::new(instance, workers, limits)?,
        })
    }

    /// 将调用方意图关联到唯一授权, 并仅为首次接纳尝试派发
    ///
    /// # 错误
    /// 身份冲突或容量不足时返回错误. 若 Authority 已接纳而 Work 拒绝入队,
    /// 请求仍保留为 Accepted; 不回滚事实, 也不自动重投或新建授权
    pub fn submit(
        &mut self,
        operation: Operation<P>,
        attempt: AttemptId,
    ) -> Result<Submission<P, O, E>, AgentError> {
        let id = operation.operation_id;
        let accepted = self.authority.submit(
            Delivery::new(
                self.instance,
                self.instance,
                Message::SubmitOperation(operation),
            ),
            attempt,
        )?;
        if accepted.admission == Admission::New {
            self.executor.accept(accepted.dispatch.clone())?;
            self.authority.mark_dispatched(id)?;
        }
        Ok(accepted)
    }

    /// 启动可运行任务并收录下一份证据; 没有在途任务时返回空值
    ///
    /// 取消本次等待不会取消已经启动的执行. 执行函数是直接传入的普通函数,
    /// 不建立能力描述, 注册表或动态处理器接口
    ///
    /// # 错误
    /// 驱动异常或证据无法采用时返回错误; 不转换成普通任务失败或重新执行
    pub async fn next_report<F, Fut>(
        &mut self,
        execute: F,
    ) -> Result<Option<Delivery<P, O, E>>, AgentError>
    where
        F: Fn(DispatchAttempt<P>) -> Fut,
        Fut: Future<Output = SubmitReport<O, E>> + Send + 'static,
    {
        self.executor.start_ready(execute);
        let Some(report) = self.executor.complete_next().await? else {
            return Ok(None);
        };
        self.authority.receive_report(report.clone())?;
        Ok(Some(report))
    }

    /// 按稳定 OperationId 查询当前观察, 不暴露可变底层状态
    pub fn operation(&self, id: OperationId) -> Option<&OperationView<P, O, E>> {
        self.authority.operation(id)
    }

    /// 查询已经由 Authority 保留的执行证据
    pub fn report(&self, id: ReportId) -> Option<&Delivery<P, O, E>> {
        self.authority.report(id)
    }

    /// 只标记等待超时, 不取消执行或产生第二次授权
    ///
    /// # 错误
    /// 未保留该请求时返回错误
    pub fn mark_wait_timeout(&mut self, id: OperationId) -> Result<(), AgentError> {
        self.authority.mark_wait_timeout(id)?;
        Ok(())
    }
}

/// 应用用例错误, 独立于执行结果中的业务错误
#[derive(Debug, Error)]
pub enum AgentError {
    /// 接纳, 派发或证据关联不满足要求
    #[error(transparent)]
    State(#[from] StateError),
    /// 后台执行驱动异常
    #[error(transparent)]
    Executor(#[from] ExecutorError),
}

/// 显式启用的固定假任务与 v0 JSON 测试支持, 不属于通用 Agent 契约
#[cfg(feature = "test-support")]
pub mod testing;
