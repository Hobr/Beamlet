//! 同进程内一个或多个 Work 的有界 Tokio 驱动, 不认识任何具体任务

use crate::{
    id::NodeInstanceId,
    memory::{Limits, StateError, Work, WorkPhase},
    model::{Delivery, DispatchAttempt, Message, SubmitReport},
};
use std::{collections::HashMap, future::Future};
use thiserror::Error;
use tokio::task::{JoinError, JoinSet};

/// 多个本地 Work 共用完成队列; 每个 Work 仍有独立排队与并发上限
///
/// 本对象没有网络或恢复机制. 丢弃它会中止尚未完成的任务并丢失状态
#[derive(Debug)]
pub struct Executor<P, O, E> {
    workers: HashMap<NodeInstanceId, Work<P, O, E>>,
    tasks: JoinSet<Delivery<P, O, E>>,
}

impl<P, O, E> Executor<P, O, E>
where
    P: Clone + Eq + Send + 'static,
    O: Clone + Eq + Send + 'static,
    E: Clone + Eq + Send + 'static,
{
    /// 按静态实例列表创建本地执行驱动
    ///
    /// # 错误
    /// 实例为空, 重复或资源上限无效时返回错误
    pub fn new(
        authority: NodeInstanceId,
        workers: Vec<NodeInstanceId>,
        limits: Limits,
    ) -> Result<Self, StateError> {
        limits.validate()?;
        let mut records = HashMap::new();
        for instance in workers {
            if records
                .insert(instance, Work::new(instance, authority, limits)?)
                .is_some()
            {
                return Err(StateError::InvalidWorkers);
            }
        }
        if records.is_empty() {
            return Err(StateError::InvalidWorkers);
        }
        Ok(Self {
            workers: records,
            tasks: JoinSet::new(),
        })
    }

    /// 校验实例绑定并入队, 不创建后台任务
    ///
    /// # 错误
    /// 目标, 授权, 定义或容量不满足要求时返回错误
    pub fn accept(&mut self, delivery: Delivery<P, O, E>) -> Result<WorkPhase, StateError> {
        self.workers
            .get_mut(&delivery.target_instance_id)
            .ok_or(StateError::WrongTarget)?
            .accept(delivery)
    }

    /// 仅在取得槽位后调用执行函数; 不注册处理器或创建无限等待许可的任务
    ///
    /// 执行函数接收普通授权, 并负责返回带有身份与效果证据的报告
    /// 报告仍须通过 Work 的关联与阶段校验
    ///
    /// # 恐慌
    /// 有任务可启动却不在 Tokio 运行时内, 或执行函数构造过程发生恐慌时终止
    pub fn start_ready<F, Fut>(&mut self, execute: F) -> usize
    where
        F: Fn(DispatchAttempt<P>) -> Fut,
        Fut: Future<Output = SubmitReport<O, E>> + Send + 'static,
    {
        let mut started = 0;
        for worker in self.workers.values_mut() {
            while let Some(dispatch) = worker.start_next() {
                let Message::DispatchAttempt(attempt) = dispatch.message else {
                    unreachable!("Work queues only authorizations");
                };
                let task = execute(attempt);
                self.tasks.spawn(async move {
                    Delivery::new(
                        dispatch.target_instance_id,
                        dispatch.source_instance_id,
                        Message::SubmitReport(task.await),
                    )
                });
                started += 1;
            }
        }
        started
    }

    /// 缓存一份完成证据后返回; 取消等待不会取消后台任务
    ///
    /// 无在途任务时返回空值; 队列中的任务须先由调用方显式启动
    ///
    /// # 错误
    /// 后台异常或证据不合法时返回内部错误, 调用方应停止驱动, 不自动重跑
    pub async fn complete_next(&mut self) -> Result<Option<Delivery<P, O, E>>, ExecutorError> {
        let Some(completed) = self.tasks.join_next().await else {
            return Ok(None);
        };
        let delivery = completed?;
        self.workers
            .get_mut(&delivery.source_instance_id)
            .ok_or(StateError::InvalidBinding)?
            .complete(delivery.clone())?;
        Ok(Some(delivery))
    }

    /// 已启动且尚未缓存完成证据的任务数
    pub fn in_flight(&self) -> usize {
        self.tasks.len()
    }

    /// 只读访问某个 Work 的阶段与缓存证据
    pub fn work(&self, instance: NodeInstanceId) -> Option<&Work<P, O, E>> {
        self.workers.get(&instance)
    }
}

/// 驱动错误, 不是业务执行结果
#[derive(Debug, Error)]
pub enum ExecutorError {
    /// Tokio 任务异常退出, 不推断执行效果
    #[error("execution task terminated unexpectedly")]
    Task(#[from] JoinError),
    /// 收录证据时违反领域或内存规则
    #[error(transparent)]
    State(#[from] StateError),
}
