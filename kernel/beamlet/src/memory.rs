//! 有界内存账本与静态路由, 不包含编码, 网络或任务种类

/// 领域状态由纯 Kernel 定义
pub use beamlet_kernel::state::{OperationPhase, WaitStatus, WorkerPhase};
use beamlet_kernel::{
    id::{AttemptId, OperationId, ReportId, RoleInstanceId},
    model::{Delivery, DispatchAttempt, Message},
    state::RuleError,
};
use std::collections::{HashMap, HashSet, VecDeque};
use thiserror::Error;

/// 内存记录, 排队与运行槽位的独立上限, 不限制具体编码字节
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Limits {
    /// 每种身份记录表的容量上限
    pub max_records: usize,
    /// 每个 Worker 的等待队列上限
    pub queue_capacity: usize,
    /// 每个 Worker 的在途执行上限
    pub max_concurrency: usize,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            max_records: 1024,
            queue_capacity: 256,
            max_concurrency: 8,
        }
    }
}
impl Limits {
    /// 检查上限是否允许推进
    ///
    /// # 错误
    /// 任一上限为零时返回错误
    pub fn validate(&self) -> Result<(), StateError> {
        if self.max_records == 0 || self.queue_capacity == 0 || self.max_concurrency == 0 {
            return Err(StateError::InvalidLimits);
        }
        Ok(())
    }
}

/// Authority 从保留的请求记录中提供的只读视图
#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub struct OperationView<P, O, E> {
    /// 已固定的执行授权; 克隆它不会创建新的 Attempt
    pub dispatch: Delivery<P, O, E>,
    /// Authority 最近一次已知的观察状态
    pub phase: OperationPhase,
    /// 等待超时不代表执行已经结束
    pub wait_status: WaitStatus,
    /// 本原型选作观察结果的第一份有效 Report
    pub adopted_report: Option<ReportId>,
}

/// 区分请求创建了新授权, 还是复用了原有授权
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum Admission {
    /// 调用方可以派发本次新建的执行授权
    New,
    /// 未创建新授权, 也未触发自动派发
    Duplicate,
}

impl std::fmt::Display for Admission {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::New => "首次接纳",
            Self::Duplicate => "重复 Operation",
        })
    }
}

/// 将客户端请求接纳到内存后的结果
#[derive(Clone, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub struct Submission<P, O, E> {
    /// 区分首次接纳与重复请求查询
    pub admission: Admission,
    /// 原有执行授权, 包含保持不变的目标运行实例
    pub dispatch: Delivery<P, O, E>,
}

/// Authority 对收到的 Report 作出的处理决定, 不是执行结果
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[non_exhaustive]
pub enum ReportDisposition {
    /// 首份有效 Report 已保留, 并被选作观察结果
    Adopted,
    /// 额外证据已保留, 不替换已选结果
    Additional,
    /// 相同的 Report 已经保留
    Duplicate,
}

impl std::fmt::Display for ReportDisposition {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Adopted => "已收录并采用",
            Self::Additional => "已收录额外证据",
            Self::Duplicate => "重复 Report",
        })
    }
}

/// 非持久化 Authority, 使用静态轮询, 每个请求只授权一个 Attempt
#[derive(Debug)]
pub struct Authority<P, O, E> {
    instance: RoleInstanceId,
    workers: Vec<RoleInstanceId>,
    next_worker: usize,
    limits: Limits,
    operations: HashMap<OperationId, OperationView<P, O, E>>,
    reports: HashMap<ReportId, Delivery<P, O, E>>,
}

impl<P: Clone + Eq, O: Clone + Eq, E: Clone + Eq> Authority<P, O, E> {
    /// 使用非空的静态 Worker 运行实例列表创建有界记录表
    ///
    /// # 错误
    /// 资源上限无效, Worker 列表为空或实例身份重复时返回错误
    pub fn new(
        instance: RoleInstanceId,
        workers: Vec<RoleInstanceId>,
        limits: Limits,
    ) -> Result<Self, StateError> {
        limits.validate()?;
        if workers.is_empty()
            || workers.iter().copied().collect::<HashSet<_>>().len() != workers.len()
        {
            return Err(StateError::InvalidWorkers);
        }
        Ok(Self {
            instance,
            workers,
            next_worker: 0,
            limits,
            operations: HashMap::new(),
            reports: HashMap::new(),
        })
    }

    /// 预览接纳与静态路由, 不保存请求, 也不推进轮询
    ///
    /// 新请求的 AttemptId 由调用方提供; 重复提交会忽略此候选 ID
    /// 本方法不发送网络消息
    ///
    /// # 错误
    /// 消息格式无效, 目标错误, 身份冲突或记录表已满时返回错误,
    /// 不修改已保留状态, 也不推进轮询位置
    pub fn preview_submit(
        &self,
        envelope: &Delivery<P, O, E>,
        attempt_id: AttemptId,
    ) -> Result<Submission<P, O, E>, StateError> {
        envelope.validate()?;
        if envelope.target_instance_id != self.instance {
            return Err(StateError::WrongTarget);
        }
        let Message::SubmitOperation(operation) = &envelope.message else {
            return Err(StateError::WrongMessage);
        };
        if let Some(existing) = self.operations.get(&operation.operation_id) {
            let Message::DispatchAttempt(attempt) = &existing.dispatch.message else {
                unreachable!("Authority 只能保留 Attempt 信封");
            };
            if attempt.operation != *operation {
                return Err(StateError::OperationConflict);
            }
            return Ok(Submission {
                admission: Admission::Duplicate,
                dispatch: existing.dispatch.clone(),
            });
        }
        if self.operations.values().any(|view| {
            matches!(&view.dispatch.message, Message::DispatchAttempt(attempt) if attempt.attempt_id == attempt_id)
        }) {
            return Err(StateError::AttemptConflict);
        }
        if self.operations.len() >= self.limits.max_records {
            return Err(StateError::Capacity);
        }
        let dispatch = Delivery::new(
            self.instance,
            self.workers[self.next_worker],
            Message::DispatchAttempt(DispatchAttempt {
                attempt_id,
                operation: operation.clone(),
            }),
        );
        Ok(Submission {
            admission: Admission::New,
            dispatch,
        })
    }

    /// 原子地接纳预览所描述的请求; 重复请求不推进轮询
    ///
    /// # 错误
    /// 身份, 绑定或容量不合法时返回错误, 不修改记录
    pub fn submit(
        &mut self,
        envelope: Delivery<P, O, E>,
        attempt_id: AttemptId,
    ) -> Result<Submission<P, O, E>, StateError> {
        let accepted = self.preview_submit(&envelope, attempt_id)?;
        if accepted.admission == Admission::Duplicate {
            return Ok(accepted);
        }
        let Message::DispatchAttempt(attempt) = &accepted.dispatch.message else {
            unreachable!("预览只能返回 Attempt");
        };
        self.operations.insert(
            attempt.operation.operation_id,
            OperationView {
                dispatch: accepted.dispatch.clone(),
                phase: OperationPhase::Accepted,
                wait_status: WaitStatus::Waiting,
                adopted_report: None,
            },
        );
        self.next_worker = (self.next_worker + 1) % self.workers.len();
        Ok(accepted)
    }

    /// 记录尝试派发, 不回退已经收到证据的状态
    ///
    /// # 错误
    /// 此 Authority 尚未接纳该 Operation 时返回错误
    pub fn mark_dispatched(&mut self, operation_id: OperationId) -> Result<(), StateError> {
        let view = self
            .operations
            .get_mut(&operation_id)
            .ok_or(StateError::UnknownOperation)?;
        if view.phase == OperationPhase::Accepted {
            view.phase = OperationPhase::Dispatched;
        }
        Ok(())
    }

    /// 记录本地等待超时, 不取消执行, 也不创建新授权
    ///
    /// # 错误
    /// 没有保留该 Operation 时返回错误
    pub fn mark_wait_timeout(&mut self, operation_id: OperationId) -> Result<(), StateError> {
        self.operations
            .get_mut(&operation_id)
            .ok_or(StateError::UnknownOperation)?
            .wait_status = WaitStatus::TimedOut;
        Ok(())
    }

    /// 校验绑定并保留证据, 即使本地等待已经超时
    ///
    /// 首份有效 Report 被选作观察结果, 不自动解释为业务成功
    /// 后续 Report 不会静默替换它
    ///
    /// # 错误
    /// 绑定无效, 相同 ReportId 的内容冲突, 证据记录表已满,
    /// 或领域证据无效时返回错误, 不修改已有证据
    pub fn receive_report(
        &mut self,
        envelope: Delivery<P, O, E>,
    ) -> Result<ReportDisposition, StateError> {
        envelope.validate()?;
        if envelope.target_instance_id != self.instance {
            return Err(StateError::WrongTarget);
        }
        let Message::SubmitReport(report) = &envelope.message else {
            return Err(StateError::WrongMessage);
        };
        let view = self
            .operations
            .get_mut(&report.operation_id)
            .ok_or(StateError::InvalidBinding)?;
        let Message::DispatchAttempt(attempt) = &view.dispatch.message else {
            unreachable!("Authority 只能保留 Attempt 信封");
        };
        if attempt.attempt_id != report.attempt_id
            || view.dispatch.target_instance_id != envelope.source_instance_id
        {
            return Err(StateError::InvalidBinding);
        }
        if let Some(existing) = self.reports.get(&report.report_id) {
            return if *existing == envelope {
                Ok(ReportDisposition::Duplicate)
            } else {
                Err(StateError::ReportConflict)
            };
        }
        if self.reports.len() >= self.limits.max_records {
            return Err(StateError::Capacity);
        }
        let disposition = if view.adopted_report.is_none() {
            view.adopted_report = Some(report.report_id);
            ReportDisposition::Adopted
        } else {
            ReportDisposition::Additional
        };
        view.phase = OperationPhase::Reported;
        self.reports.insert(report.report_id, envelope);
        Ok(disposition)
    }

    /// 返回已保留状态的只读视图, 不暴露记录表的可变访问
    pub fn operation(&self, id: OperationId) -> Option<&OperationView<P, O, E>> {
        self.operations.get(&id)
    }

    /// 返回已保留的 Report, 包括未被采用为结果的证据
    pub fn report(&self, id: ReportId) -> Option<&Delivery<P, O, E>> {
        self.reports.get(&id)
    }
}

#[derive(Debug)]
struct WorkerRecord<P, O, E> {
    dispatch: Delivery<P, O, E>,
    phase: WorkerPhase,
    report: Option<ReportId>,
}

/// 单个 Worker 运行实例使用的有界内存队列与去重记录表
#[derive(Debug)]
pub struct Worker<P, O, E> {
    instance: RoleInstanceId,
    authority: RoleInstanceId,
    limits: Limits,
    attempts: HashMap<AttemptId, WorkerRecord<P, O, E>>,
    reports: HashMap<ReportId, Delivery<P, O, E>>,
    queue: VecDeque<AttemptId>,
    running: usize,
}

impl<P: Clone + Eq, O: Clone + Eq, E: Clone + Eq> Worker<P, O, E> {
    /// 创建空的 Worker, 并绑定到配置的 Authority 运行实例
    ///
    /// # 错误
    /// 资源上限无效时返回错误
    pub fn new(
        instance: RoleInstanceId,
        authority: RoleInstanceId,
        limits: Limits,
    ) -> Result<Self, StateError> {
        limits.validate()?;
        Ok(Self {
            instance,
            authority,
            limits,
            attempts: HashMap::new(),
            reports: HashMap::new(),
            queue: VecDeque::new(),
            running: 0,
        })
    }

    /// 将新授权入队, 或返回已保留的相同 Attempt 的状态
    ///
    /// 拒绝仅表示本次交付未入队, 不撤销原执行授权
    /// 入队被拒绝时不生成执行 Report, 也不运行处理函数
    ///
    /// # 错误
    /// 实例错误, 消息无效, 身份冲突或记录与队列容量耗尽时返回错误
    /// 容量耗尽后仍允许查询重复请求
    pub fn accept(&mut self, envelope: Delivery<P, O, E>) -> Result<WorkerPhase, StateError> {
        envelope.validate()?;
        if envelope.target_instance_id != self.instance {
            return Err(StateError::WrongTarget);
        }
        if envelope.source_instance_id != self.authority {
            return Err(StateError::UntrustedAuthority);
        }
        let Message::DispatchAttempt(attempt) = &envelope.message else {
            return Err(StateError::WrongMessage);
        };
        let id = attempt.attempt_id;
        if let Some(existing) = self.attempts.get(&id) {
            return if existing.dispatch == envelope {
                Ok(existing.phase)
            } else {
                Err(StateError::AttemptConflict)
            };
        }
        if self.attempts.len() >= self.limits.max_records {
            return Err(StateError::Capacity);
        }
        if self.queue.len() >= self.limits.queue_capacity {
            return Err(StateError::QueueFull);
        }
        self.attempts.insert(
            id,
            WorkerRecord {
                dispatch: envelope,
                phase: WorkerPhase::Queued,
                report: None,
            },
        );
        self.queue.push_back(id);
        Ok(WorkerPhase::Queued)
    }

    /// 有空闲并发槽位时取出一个排队中的 Attempt
    ///
    /// 仅修改显式状态, 不创建任务, 不等待, 也不运行工具
    pub fn start_next(&mut self) -> Option<Delivery<P, O, E>> {
        if self.running >= self.limits.max_concurrency {
            return None;
        }
        let id = self.queue.pop_front()?;
        let record = self
            .attempts
            .get_mut(&id)
            .expect("排队中的 Attempt 必须有保留记录");
        record.phase = WorkerPhase::Running;
        self.running += 1;
        Some(record.dispatch.clone())
    }

    /// 记录调用方提供的证据, 同一次执行最多释放一个运行槽位
    ///
    /// 运行中的 Attempt 可以成功或失败; 排队中的 Attempt 只能在开始前明确拒绝
    /// 重复提交完全相同的完成记录不会产生额外影响
    ///
    /// # 错误
    /// 绑定无效, 证据冲突或阶段与结果组合不合法时返回错误,
    /// 不修改队列, 运行计数或缓存报告
    pub fn complete(&mut self, envelope: Delivery<P, O, E>) -> Result<(), StateError> {
        envelope.validate()?;
        if envelope.source_instance_id != self.instance
            || envelope.target_instance_id != self.authority
        {
            return Err(StateError::InvalidBinding);
        }
        let Message::SubmitReport(report) = &envelope.message else {
            return Err(StateError::WrongMessage);
        };
        let record = self
            .attempts
            .get_mut(&report.attempt_id)
            .ok_or(StateError::InvalidBinding)?;
        let Message::DispatchAttempt(attempt) = &record.dispatch.message else {
            unreachable!("Worker 只能保留 Attempt 信封");
        };
        if attempt.operation.operation_id != report.operation_id {
            return Err(StateError::InvalidBinding);
        }
        if let Some(existing) = self.reports.get(&report.report_id) {
            return if *existing == envelope {
                Ok(())
            } else {
                Err(StateError::ReportConflict)
            };
        }
        let completed = record
            .phase
            .finish(&report.result)
            .map_err(|_| StateError::InvalidTransition)?;
        match record.phase {
            WorkerPhase::Queued => self.queue.retain(|id| *id != report.attempt_id),
            WorkerPhase::Running => self.running -= 1,
            _ => return Err(StateError::InvalidTransition),
        }
        record.phase = completed;
        record.report = Some(report.report_id);
        self.reports.insert(report.report_id, envelope);
        Ok(())
    }

    /// 返回已接纳 Attempt 的当前去重状态
    pub fn phase(&self, id: AttemptId) -> Option<WorkerPhase> {
        self.attempts.get(&id).map(|record| record.phase)
    }

    /// 返回缓存的完成证据, 用于处理重复交付
    pub fn report(&self, id: AttemptId) -> Option<&Delivery<P, O, E>> {
        self.attempts
            .get(&id)?
            .report
            .and_then(|report_id| self.reports.get(&report_id))
    }
}

/// 内存原型的接纳与状态转换错误
#[derive(Debug, Error)]
pub enum StateError {
    /// 领域证据不符合纯 Kernel 的规则
    #[error(transparent)]
    Rule(#[from] RuleError),
    /// 内存上限必须为正数
    #[error("资源上限必须为正数")]
    InvalidLimits,
    /// 静态 Worker 配置为空, 或存在重复的实例身份
    #[error("Worker 列表不能为空且实例不能重复")]
    InvalidWorkers,
    /// 消息的目标是另一个进程运行实例
    #[error("消息目标与当前角色运行实例不符")]
    WrongTarget,
    /// 当前状态转换不接收此消息类型
    #[error("消息类型与预期不符")]
    WrongMessage,
    /// 发送方不是配置的 Authority 运行实例
    #[error("发送方不是配置的 Authority")]
    UntrustedAuthority,
    /// 该 Operation 身份已经绑定到不同的定义
    #[error("Operation 身份与已保留定义冲突")]
    OperationConflict,
    /// 同一 Attempt 身份被用于不同的绑定或请求
    #[error("Attempt 身份与已保留授权冲突")]
    AttemptConflict,
    /// 同一 Report 身份被用于不同的证据
    #[error("Report 身份与已保留证据冲突")]
    ReportConflict,
    /// 证据与保留的 Operation, Attempt 或节点绑定不匹配
    #[error("证据与已保留授权不符")]
    InvalidBinding,
    /// 身份记录表已满; 不会淘汰已有记录
    #[error("身份记录保留容量已满")]
    Capacity,
    /// 等待队列已满, 本次新交付未被接纳
    #[error("Worker 队列已满")]
    QueueFull,
    /// 不存在具有此身份的已接纳请求
    #[error("Operation 未被保留")]
    UnknownOperation,
    /// 当前 Worker 阶段不允许提交此完成结果
    #[error("完成结果与 Worker 当前阶段不符")]
    InvalidTransition,
}
