//! 静态 Authority/Worker 进程, 只在应用边界交付已有授权和证据

use std::{collections::HashMap, sync::Arc, time::Duration};

use anyhow::{Context, Result, bail, ensure};
use beamlet_agent::{
    Admission, Agent, AgentError, Authority, StateError, Worker,
    id::{OperationId, RoleInstanceId},
    model::{Delivery, DispatchAttempt, Effect, ExecutionResult, Message, SubmitReport},
    testing::{
        hello::{self, Dispatch, Request, Response, ResponseMessage, Task},
        protocol::Limits as ProtocolLimits,
    },
};
use beamlet_message_zenoh::{Limits, Transport};
use tokio::{
    task::JoinSet,
    time::{Instant, MissedTickBehavior, interval, timeout},
};
use uuid::Uuid;

const NODE_INBOX_PREFIX: &str = "beamlet/v0/node/inbox/";
const SEND_TIMEOUT: Duration = Duration::from_secs(10);

type HelloAgent = Agent<Task, String, String>;

type HelloAuthority = Authority<Task, String, String>;

// 留出 Console 的 10 秒等待预算, 只结束本次观察, 不取消 Worker
const REPLY_WAIT: Duration = Duration::from_secs(5);

struct Waiter {
    operation: OperationId,
    console: String,
    deadline: Instant,
}

enum SendPurpose {
    Dispatch(OperationId),
    Reply,
}

struct Outgoing {
    destination: String,
    bytes: Vec<u8>,
    purpose: SendPurpose,
}

type Sends = JoinSet<(SendPurpose, Result<()>)>;

/// 启动只接纳请求和收录证据的静态 Authority 进程
///
/// # 错误
/// 配置, 会话, 驱动状态或后台任务无法继续时返回错误
pub async fn run_authority(
    endpoint: &str,
    instance: RoleInstanceId,
    workers: Vec<RoleInstanceId>,
) -> Result<()> {
    let transport = Arc::new(
        Transport::listen(
            endpoint,
            &format!("{NODE_INBOX_PREFIX}*"),
            Limits::default(),
        )
        .await?,
    );
    serve_authority(
        transport,
        instance,
        workers,
        HashMap::new(),
        NODE_INBOX_PREFIX.to_owned(),
    )
    .await
}

pub(crate) async fn serve_authority(
    transport: Arc<Transport>,
    instance: RoleInstanceId,
    workers: Vec<RoleInstanceId>,
    local_workers: HashMap<RoleInstanceId, Worker<Task, String, String>>,
    request_prefix: String,
) -> Result<()> {
    serve_authority_pair(
        transport,
        None,
        instance,
        workers,
        local_workers,
        request_prefix,
    )
    .await
}

pub(crate) async fn serve_authority_pair(
    transport: Arc<Transport>,
    report_transport: Option<Transport>,
    instance: RoleInstanceId,
    workers: Vec<RoleInstanceId>,
    mut local_workers: HashMap<RoleInstanceId, Worker<Task, String, String>>,
    request_prefix: String,
) -> Result<()> {
    let limits = beamlet_agent::Limits::default();
    let mut authority = HelloAuthority::new(instance, workers, limits)?;
    let protocol = ProtocolLimits::default();
    let reports = report_inbox(instance);
    let mut waiters: Vec<Waiter> = Vec::new();
    let mut sends = Sends::new();
    let mut tick = interval(Duration::from_millis(100));
    tick.set_missed_tick_behavior(MissedTickBehavior::Skip);
    println!("Authority 已就绪: 实例={instance}");
    println!(
        "内存记录上限={}; 等待回复与发送任务各自上限={}",
        limits.max_records, limits.queue_capacity
    );

    loop {
        flush_replies(
            &mut authority,
            &mut waiters,
            &mut sends,
            &transport,
            &protocol,
            limits.queue_capacity,
        )?;
        tokio::select! {
            received = async {
                if let Some(reports) = &report_transport {
                    tokio::select! {
                        received = transport.recv_message() => received,
                        received = reports.recv_message() => received,
                    }
                } else {
                    transport.recv_message().await
                }
            } => {
                let message = received.context("Authority 接收消息失败")?;
                if message.key_expr == reports {
                    let delivery = match hello::decode_report(&message.payload, &protocol) {
                        Ok(delivery) => delivery,
                        Err(error) => {
                            eprintln!("已忽略无效 Report: {error}");
                            continue;
                        }
                    };
                    match authority.receive_report(delivery) {
                        Ok(disposition) => println!("Authority 已接收 Report: {disposition}"),
                        Err(error) => eprintln!("Report 未收录: {error}"),
                    }
                    continue;
                }
                let Some(console) = message.key_expr.strip_prefix(&request_prefix) else {
                    continue;
                };
                if console.len() != 32 || !console.bytes().all(|byte| byte.is_ascii_hexdigit()) {
                    eprintln!("已忽略无效 Console 路由: {console:?}");
                    continue;
                }
                let request = match Request::from_json(&message.payload, &protocol) {
                    Ok(request) => request,
                    Err(error) => {
                        eprintln!("Operation 无效, 未接纳: {error}");
                        continue;
                    }
                };
                // 先检查发送任务上限, 不在无界后台任务中接纳更多请求
                if sends.len() >= limits.queue_capacity {
                    eprintln!("Operation 未提交: 发送任务已满; Operation={}", request.operation_id());
                    continue;
                }
                let operation = request.operation_id();
                let adopted = authority.operation(operation).and_then(|view| view.adopted_report);
                let already_waiting = waiters.iter().any(|waiter| waiter.operation == operation && waiter.console == console);
                if adopted.is_none() && !already_waiting && waiters.len() >= limits.queue_capacity {
                    let response = Response::new(ResponseMessage::SubmissionError {
                        operation_id: Uuid::from_u128(operation.as_u128()),
                        error: format!("等待回复记录已满; 已保留阶段={}; 不自动重试", authority.operation(operation).map(|view| view.phase.to_string()).unwrap_or_else(|| "未接纳".to_owned())),
                    });
                    queue_reply(&mut sends, &transport, console, response, &protocol)?;
                    continue;
                }
                let submission = match authority.submit(request.operation(), Uuid::new_v4().as_u128().into()) {
                    Ok(submission) => submission,
                    Err(error @ (StateError::Capacity | StateError::QueueFull | StateError::OperationConflict | StateError::AttemptConflict)) => {
                        let response = Response::new(ResponseMessage::SubmissionError {
                            operation_id: Uuid::from_u128(operation.as_u128()),
                            error: format!("{error}; 已保留阶段={}; 不自动重试", authority.operation(operation).map(|view| view.phase.to_string()).unwrap_or_else(|| "未接纳".to_owned())),
                        });
                        queue_reply(&mut sends, &transport, console, response, &protocol)?;
                        continue;
                    }
                    Err(error) => return Err(error.into()),
                };
                println!("Authority 已接纳: Operation={operation} Worker={} 接纳结果={}", submission.dispatch.target_instance_id, submission.admission);
                if let Some(report_id) = adopted {
                    let report = authority.report(report_id).context("已采用的 Report 缺失")?;
                    queue_reply(&mut sends, &transport, console, response_for(report, operation)?, &protocol)?;
                    continue;
                }
                if !already_waiting {
                    waiters.push(Waiter { operation, console: console.to_owned(), deadline: Instant::now() + REPLY_WAIT });
                }
                if submission.admission == Admission::New {
                    if let Some(worker) = local_workers.get_mut(&submission.dispatch.target_instance_id) {
                        let cached = worker.receive_dispatch(submission.dispatch.clone())?;
                        authority.mark_dispatched(operation)?;
                        let report = match cached {
                            Some(report) => report,
                            None => worker.next_report(execute_hello).await?.context("本地 Worker 未产生 Report")?,
                        };
                        authority.receive_report(report)?;
                        println!("本地类型化交付: Operation={operation}");
                        continue;
                    }
                    let bytes = Dispatch::from_delivery(&submission.dispatch)?.to_json(&protocol)?;
                    queue_send(&mut sends, &transport, Outgoing {
                        destination: worker_inbox(submission.dispatch.target_instance_id),
                        bytes,
                        purpose: SendPurpose::Dispatch(operation),
                    });
                }
            }
            completed = sends.join_next(), if !sends.is_empty() => {
                let (purpose, result) = completed.context("发送完成记录缺失")?.context("发送任务失败")?;
                match (purpose, result) {
                    (SendPurpose::Dispatch(operation), Ok(())) => {
                        authority.mark_dispatched(operation)?;
                        println!("Authority 已发出授权: Operation={operation}; 尚无证据确认 Worker 接纳");
                    }
                    (SendPurpose::Dispatch(operation), Err(error)) => eprintln!("授权发送未确认: Operation={operation}; {error}; 保留原记录, 不重试或创建新授权"),
                    (SendPurpose::Reply, Err(error)) => eprintln!("Console 回复未确认: {error}; 证据已保留, 不重试"),
                    (SendPurpose::Reply, Ok(())) => {}
                }
            }
            _ = tick.tick() => {}
            signal = tokio::signal::ctrl_c() => {
                signal?;
                return Ok(());
            }
        }
    }
}

fn flush_replies(
    authority: &mut HelloAuthority,
    waiters: &mut Vec<Waiter>,
    sends: &mut Sends,
    transport: &Arc<Transport>,
    protocol: &ProtocolLimits,
    capacity: usize,
) -> Result<()> {
    while sends.len() < capacity {
        let now = Instant::now();
        let ready = waiters.iter().position(|waiter| {
            authority
                .operation(waiter.operation)
                .is_some_and(|view| view.adopted_report.is_some())
                || waiter.deadline <= now
        });
        let Some(index) = ready else { break };
        let waiter = waiters.swap_remove(index);
        let report_id = authority
            .operation(waiter.operation)
            .and_then(|view| view.adopted_report);
        let response = if let Some(report_id) = report_id {
            let report = authority
                .report(report_id)
                .context("已采用的 Report 缺失")?;
            response_for(report, waiter.operation)?
        } else {
            authority.mark_wait_timeout(waiter.operation)?;
            println!(
                "Authority 待定: Operation={}; 不自动重试或创建新授权",
                waiter.operation
            );
            Response::new(ResponseMessage::Pending {
                operation_id: Uuid::from_u128(waiter.operation.as_u128()),
            })
        };
        queue_reply(sends, transport, &waiter.console, response, protocol)?;
    }
    Ok(())
}

fn queue_reply(
    sends: &mut Sends,
    transport: &Arc<Transport>,
    console: &str,
    response: Response,
    protocol: &ProtocolLimits,
) -> Result<()> {
    queue_send(
        sends,
        transport,
        Outgoing {
            destination: format!("beamlet/v0/console/{console}/inbox"),
            bytes: response.to_json(protocol)?,
            purpose: SendPurpose::Reply,
        },
    );
    Ok(())
}

fn queue_send(sends: &mut Sends, transport: &Arc<Transport>, outgoing: Outgoing) {
    // 有界发送任务共享同一会话, 不持有 Authority 状态或锁
    let transport = Arc::clone(transport);
    sends.spawn(async move {
        let result = send(&transport, &outgoing.destination, outgoing.bytes).await;
        (outgoing.purpose, result)
    });
}

async fn send(transport: &Transport, destination: &str, bytes: Vec<u8>) -> Result<()> {
    timeout(SEND_TIMEOUT, async {
        let sender = transport.sender(destination).await?;
        sender.wait_for_receiver().await?;
        sender.send(bytes).await?;
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("发送超时; 不自动重试")?
}

/// 启动只执行绑定 Authority 授权的静态 Worker 进程
///
/// # 错误
/// 配置, 连接, 接收或内部执行驱动失败时返回错误
pub async fn run_worker(
    endpoint: &str,
    instance: RoleInstanceId,
    authority: RoleInstanceId,
) -> Result<()> {
    let inbox = worker_inbox(instance);
    let transport = timeout(
        SEND_TIMEOUT,
        Transport::connect(endpoint, &inbox, Limits::default()),
    )
    .await
    .context("Worker 连接超时")??;
    serve_worker(transport, instance, authority).await
}

pub(crate) async fn serve_worker(
    transport: Transport,
    instance: RoleInstanceId,
    authority: RoleInstanceId,
) -> Result<()> {
    let mut worker = Worker::<Task, String, String>::new(
        authority,
        vec![instance],
        beamlet_agent::Limits::default(),
    )?;
    let protocol = ProtocolLimits::default();
    let inbox = worker_inbox(instance);
    println!("Worker 已就绪: 实例={instance} Authority={authority}");
    loop {
        let message = tokio::select! {
            received = transport.recv_message() => received.context("Worker 接收授权失败")?,
            signal = tokio::signal::ctrl_c() => {
                signal?;
                return Ok(());
            }
        };
        ensure!(message.key_expr == inbox, "Worker 消息地址与预期不符");
        let dispatch = match Dispatch::from_json(&message.payload, &protocol) {
            Ok(dispatch) => dispatch.delivery(),
            Err(error) => {
                eprintln!("授权无效, 未接纳: {error}");
                continue;
            }
        };
        let cached = match worker.receive_dispatch(dispatch) {
            Ok(cached) => cached,
            Err(error) => {
                eprintln!("授权未接纳: {error}");
                continue;
            }
        };
        let report = match cached {
            Some(report) => report,
            None => worker
                .next_report(execute_hello)
                .await?
                .context("Worker 接纳后未产生 Report")?,
        };
        let Message::SubmitReport(evidence) = &report.message else {
            anyhow::bail!("Worker 完成结果不包含 Report");
        };
        println!(
            "Worker 已缓存 Report: Operation={} Attempt={} Report={}",
            evidence.operation_id, evidence.attempt_id, evidence.report_id
        );
        let bytes = hello::encode_report(&report, &protocol)?;
        if let Err(error) = send(&transport, &report_inbox(authority), bytes).await {
            eprintln!("Report 发送未确认: {error}; 已缓存, 不自动重试");
        }
    }
}

pub(crate) fn worker_inbox(instance: RoleInstanceId) -> String {
    format!(
        "beamlet/v0/worker/{}/inbox",
        Uuid::from_u128(instance.as_u128()).simple()
    )
}

pub(crate) fn report_inbox(instance: RoleInstanceId) -> String {
    format!(
        "{NODE_INBOX_PREFIX}reports-{}",
        Uuid::from_u128(instance.as_u128()).simple()
    )
}

/// 启动原有的本地 Hello 演示, Authority 与 Worker 仍在同一进程
///
/// # 错误
/// 配置, 接纳, 内部驱动或收发出现无法处理的错误时返回错误
pub async fn run_local(endpoint: &str) -> Result<()> {
    let inbox = format!("{NODE_INBOX_PREFIX}*");
    let transport = Transport::listen(endpoint, &inbox, Limits::default())
        .await
        .context("启动 Node 监听失败")?;
    let authority = Uuid::new_v4().as_u128().into();
    let worker = Uuid::new_v4().as_u128().into();
    let runtime_limits = beamlet_agent::Limits::default();
    let mut agent = HelloAgent::new(authority, vec![worker], runtime_limits)?;
    let protocol_limits = ProtocolLimits::default();
    println!("Node 正在监听: {endpoint}");
    println!(
        "内存 Authority={authority} Worker={worker}; Operation 保留上限={}",
        runtime_limits.max_records
    );

    loop {
        let message = tokio::select! {
            received = transport.recv_message() => received.context("接收 Console 消息失败")?,
            signal = tokio::signal::ctrl_c() => {
                signal?;
                return Ok(());
            }
        };
        let Some(console_id) = message.key_expr.strip_prefix(NODE_INBOX_PREFIX) else {
            eprintln!("已忽略非预期消息地址: {:?}", message.key_expr);
            continue;
        };
        // 路由 ID 只用于区分 Console, 不作为认证凭证或任意回复地址
        if console_id.len() != 32 || !console_id.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            eprintln!("已忽略无效 Console 路由: {console_id:?}");
            continue;
        }
        let request = match Request::from_json(&message.payload, &protocol_limits) {
            Ok(request) => request,
            Err(error) => {
                eprintln!("Console[{console_id}]Operation 无效, 未接纳: {error}");
                continue;
            }
        };
        let response = submit(&mut agent, &request).await?;
        let bytes = response.to_json(&protocol_limits)?;
        let destination = format!("beamlet/v0/console/{console_id}/inbox");
        let outcome = timeout(SEND_TIMEOUT, async {
            let reply = transport.sender(&destination).await?;
            reply.wait_for_receiver().await?;
            reply.send(bytes).await
        })
        .await;
        match outcome {
            Ok(Ok(())) => println!("Node -> Console[{console_id}]: 回复已发出"),
            Ok(Err(error)) => {
                eprintln!("回复 Console[{console_id}]失败, 不重试: {error}");
            }
            Err(_) => {
                eprintln!("回复 Console[{console_id}]超时, 不重试");
            }
        }
    }
}

async fn submit(agent: &mut HelloAgent, request: &Request) -> Result<Response> {
    let operation_id = request.operation_id();
    let submission = match agent.submit(request.operation(), Uuid::new_v4().as_u128().into()) {
        Ok(submission) => submission,
        Err(AgentError::State(
            error @ (StateError::Capacity
            | StateError::QueueFull
            | StateError::OperationConflict
            | StateError::AttemptConflict),
        )) => {
            let phase = agent
                .operation(operation_id)
                .map(|view| view.phase.to_string())
                .unwrap_or_else(|| "未接纳".to_owned());
            return Ok(Response::new(ResponseMessage::SubmissionError {
                operation_id: Uuid::from_u128(operation_id.as_u128()),
                error: format!("{error}; 已保留阶段={phase}; 不自动重试"),
            }));
        }
        Err(error) => return Err(error.into()),
    };
    let Message::DispatchAttempt(attempt) = &submission.dispatch.message else {
        bail!("提交后未保留 Attempt");
    };
    println!(
        "Authority: Operation={operation_id} Attempt={} 接纳结果={}",
        attempt.attempt_id, submission.admission
    );

    if let Some(report_id) = agent
        .operation(operation_id)
        .and_then(|view| view.adopted_report)
    {
        let retained = agent.report(report_id).context("已采用的 Report 缺失")?;
        return response_for(retained, operation_id);
    }

    // 取消网络等待不能丢弃此 Agent; 证据先收录, 再尝试交付 Console
    let Some(delivery) = agent.next_report(execute_hello).await? else {
        return Ok(Response::new(ResponseMessage::Pending {
            operation_id: Uuid::from_u128(operation_id.as_u128()),
        }));
    };
    response_for(&delivery, operation_id)
}

fn response_for(
    delivery: &Delivery<Task, String, String>,
    operation: OperationId,
) -> Result<Response> {
    let Message::SubmitReport(report) = &delivery.message else {
        bail!("完成结果不包含 Report");
    };
    ensure!(
        report.operation_id == operation,
        "Report 属于其他 Operation"
    );
    println!(
        "Authority 已收录: Operation={} Attempt={} Report={}",
        report.operation_id, report.attempt_id, report.report_id
    );
    Ok(Response::report(
        report,
        delivery.source_instance_id,
        delivery.target_instance_id,
    ))
}

async fn execute_hello(attempt: DispatchAttempt<Task>) -> SubmitReport<String, String> {
    let output = hello().to_owned();
    println!(
        "Worker 已执行 hello: Operation={} Attempt={}",
        attempt.operation.operation_id, attempt.attempt_id
    );
    SubmitReport {
        report_id: Uuid::new_v4().as_u128().into(),
        operation_id: attempt.operation.operation_id,
        attempt_id: attempt.attempt_id,
        effect: Effect::None,
        result: ExecutionResult::Succeeded { output },
    }
}

fn hello() -> &'static str {
    "World"
}
