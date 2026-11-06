//! 独立 Worker 消息入口, 执行并缓存证据, 不持有 Authority

use crate::{
    ExecutorError, Limits, StateError,
    id::RoleInstanceId,
    model::{Delivery, DispatchAttempt, Message, SubmitReport},
    state::WorkerPhase,
};
use beamlet::executor::Executor;
use std::future::Future;

/// 独立 Worker 驱动, 可以承载同一进程内静态配置的一个或多个 Worker
///
/// 调用方负责交付返回的 Report, 本对象不直接修改 Authority
/// 丢弃驱动会中止未完成的本地任务并丢失内存记录
#[derive(Debug)]
pub struct Worker<P, O, E> {
    executor: Executor<P, O, E>,
}

impl<P, O, E> Worker<P, O, E>
where
    P: Clone + Eq + Send + 'static,
    O: Clone + Eq + Send + 'static,
    E: Clone + Eq + Send + 'static,
{
    /// 为配置的 Authority 和本地 Worker 实例创建独立执行驱动
    ///
    /// # 错误
    /// 资源上限无效, Worker 列表为空或实例身份重复时返回错误
    pub fn new(
        authority: RoleInstanceId,
        workers: Vec<RoleInstanceId>,
        limits: Limits,
    ) -> Result<Self, StateError> {
        Ok(Self {
            executor: Executor::new(authority, workers, limits)?,
        })
    }

    /// 接收授权并入队, 不在接收过程中启动执行
    ///
    /// 新授权或尚未完成的重复授权返回空值
    /// 已完成的重复授权返回缓存的原 Report, 供调用方重新交付
    ///
    /// # 错误
    /// 消息, 目标, 授权绑定, 定义或容量不合法时返回错误
    pub fn receive_dispatch(
        &mut self,
        dispatch: Delivery<P, O, E>,
    ) -> Result<Option<Delivery<P, O, E>>, StateError> {
        let Message::DispatchAttempt(attempt) = &dispatch.message else {
            return Err(StateError::WrongMessage);
        };
        let attempt_id = attempt.attempt_id;
        let instance = dispatch.target_instance_id;
        let phase = self.executor.accept(dispatch)?;
        if phase == WorkerPhase::Completed {
            let report = self
                .executor
                .worker(instance)
                .and_then(|worker| worker.report(attempt_id))
                .expect("completed attempts retain their report");
            return Ok(Some(report.clone()));
        }
        Ok(None)
    }

    /// 启动可运行任务, 缓存下一份完成证据后返回待交付的 Report
    ///
    /// 没有任务时返回空值, 调用方不应在空闲时循环轮询
    /// 取消本次等待不会取消已启动执行, 也不会丢弃完成证据
    ///
    /// # 错误
    /// 后台异常或证据不合法时返回内部错误, 调用方应停止驱动
    /// 不自动生成失败 Report 或重跑
    pub async fn next_report<F, Fut>(
        &mut self,
        execute: F,
    ) -> Result<Option<Delivery<P, O, E>>, ExecutorError>
    where
        F: Fn(DispatchAttempt<P>) -> Fut,
        Fut: Future<Output = SubmitReport<O, E>> + Send + 'static,
    {
        self.executor.start_ready(execute);
        self.executor.complete_next().await
    }
}
