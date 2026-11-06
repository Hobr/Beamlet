//! 无外部效果的固定假任务 Adapter; 通用排队与后台驱动位于 kernel/beamlet

use super::{
    memory::{StateError, WorkerPhase},
    protocol::*,
};
use crate::model as domain;
use beamlet::{executor::Executor, memory::Worker};
use std::time::Duration;

/// 底层后台错误不转换成普通业务失败
pub use beamlet::executor::ExecutorError;

/// 单个 Worker 的假任务测试入口, 不持有自己的调度队列
#[derive(Debug)]
pub struct WorkerExecutor {
    inner: Executor<TestTask, Value, String>,
    instance: RoleInstanceId,
    limits: Limits,
}
impl WorkerExecutor {
    /// 创建单 Worker 测试入口
    ///
    /// # 错误
    /// 配置不合法时返回错误
    pub fn new(
        instance: RoleInstanceId,
        authority: RoleInstanceId,
        limits: Limits,
    ) -> Result<Self, StateError> {
        limits.validate()?;
        Ok(Self {
            inner: Executor::new(authority, vec![instance], limits.core())?,
            instance,
            limits,
        })
    }
    /// 入队前校验完整传输消息及固定任务的预期报告大小
    ///
    /// # 错误
    /// 格式, 绑定, 定义, 容量或预期输出不合法时不入队
    pub fn accept(&mut self, envelope: Envelope) -> Result<WorkerPhase, StateError> {
        envelope.validate(&self.limits)?;
        let delivery = envelope.to_core();
        let domain::Message::DispatchAttempt(attempt) = &delivery.message else {
            return Err(StateError::WrongMessage);
        };
        let predicted = domain::Delivery::new(
            delivery.target_instance_id,
            delivery.source_instance_id,
            domain::Message::SubmitReport(prepare(attempt).report),
        );
        Envelope::from_core(&predicted).validate(&self.limits)?;
        Ok(self.inner.accept(delivery)?)
    }
    /// 启动当前有槽位的固定任务; 调用方必须位于 Tokio 运行时内
    pub fn start_ready(&mut self) -> usize {
        self.inner.start_ready(execute)
    }
    /// 等待并缓存下一份证据; 取消等待不取消任务
    ///
    /// # 错误
    /// 底层后台异常或证据无法保存时返回错误
    pub async fn complete_next(&mut self) -> Result<Option<Envelope>, ExecutorError> {
        Ok(self
            .inner
            .complete_next()
            .await?
            .as_ref()
            .map(Envelope::from_core))
    }
    /// 已启动且尚未收录证据的任务数
    pub fn in_flight(&self) -> usize {
        self.inner.in_flight()
    }
    /// 只读查询底层 Worker 状态
    pub fn worker(&self) -> &Worker<TestTask, Value, String> {
        self.inner
            .worker(self.instance)
            .expect("single worker remains configured")
    }
    /// 按原授权查询缓存证据的协议投影
    pub fn report(&self, id: AttemptId) -> Option<Envelope> {
        self.worker().report(id).map(Envelope::from_core)
    }
}

struct Prepared {
    delay: Duration,
    report: domain::SubmitReport<Value, String>,
}
fn prepare(attempt: &domain::DispatchAttempt<TestTask>) -> Prepared {
    let (delay, result) = match &attempt.operation.task {
        TestTask::Echo(output) => (
            Duration::ZERO,
            domain::ExecutionResult::Succeeded {
                output: output.clone(),
            },
        ),
        TestTask::Delay { delay_ms, value } => (
            Duration::from_millis(*delay_ms),
            domain::ExecutionResult::Succeeded {
                output: value.clone(),
            },
        ),
        TestTask::Fail { message } => (
            Duration::ZERO,
            domain::ExecutionResult::Failed {
                error: message.clone(),
            },
        ),
    };
    Prepared {
        delay,
        report: domain::SubmitReport {
            report_id: Uuid::new_v4().as_u128().into(),
            operation_id: attempt.operation.operation_id,
            attempt_id: attempt.attempt_id,
            // 固定分支不调用外部系统, 不能推广为"失败等于无效果"
            effect: domain::Effect::None,
            result,
        },
    }
}

pub(crate) async fn execute(
    attempt: domain::DispatchAttempt<TestTask>,
) -> domain::SubmitReport<Value, String> {
    let task = prepare(&attempt);
    if !task.delay.is_zero() {
        tokio::time::sleep(task.delay).await;
    }
    task.report
}
