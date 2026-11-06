//! 静态 Authority/Work 进程, 只在应用边界交付已有授权和证据

use std::{collections::HashMap, sync::Arc, time::Duration};

use anyhow::{Context, Result, bail, ensure};
use beamlet_agent::{
    Admission, Agent, AgentError, Authority, StateError, Work,
    id::{NodeInstanceId, OperationId},
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

// 留出 Console 的 10 秒等待预算, 只结束本次观察, 不取消 Work
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
    instance: NodeInstanceId,
    workers: Vec<NodeInstanceId>,
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
    instance: NodeInstanceId,
    workers: Vec<NodeInstanceId>,
    local_workers: HashMap<NodeInstanceId, Work<Task, String, String>>,
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
    instance: NodeInstanceId,
    workers: Vec<NodeInstanceId>,
    mut local_workers: HashMap<NodeInstanceId, Work<Task, String, String>>,
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
    println!("authority ready: instance={instance}");
    println!(
        "volatile records={}; reply waiters and sends each <= {}",
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
                let message = received.context("receiving authority message")?;
                if message.key_expr == reports {
                    let delivery = match hello::decode_report(&message.payload, &protocol) {
                        Ok(delivery) => delivery,
                        Err(error) => {
                            eprintln!("ignored invalid report: {error}");
                            continue;
                        }
                    };
                    match authority.receive_report(delivery) {
                        Ok(disposition) => println!("authority report received: {disposition:?}"),
                        Err(error) => eprintln!("report not retained: {error}"),
                    }
                    continue;
                }
                let Some(console) = message.key_expr.strip_prefix(&request_prefix) else {
                    continue;
                };
                if console.len() != 32 || !console.bytes().all(|byte| byte.is_ascii_hexdigit()) {
                    eprintln!("ignored invalid console route: {console:?}");
                    continue;
                }
                let request = match Request::from_json(&message.payload, &protocol) {
                    Ok(request) => request,
                    Err(error) => {
                        eprintln!("invalid request, not accepted: {error}");
                        continue;
                    }
                };
                // 先检查发送任务上限, 不在无界后台任务中接纳更多请求
                if sends.len() >= limits.queue_capacity {
                    eprintln!("request not submitted: delivery slots full; operation={}", request.operation_id());
                    continue;
                }
                let operation = request.operation_id();
                let adopted = authority.operation(operation).and_then(|view| view.adopted_report);
                let already_waiting = waiters.iter().any(|waiter| waiter.operation == operation && waiter.console == console);
                if adopted.is_none() && !already_waiting && waiters.len() >= limits.queue_capacity {
                    let response = Response::new(ResponseMessage::SubmissionError {
                        operation_id: Uuid::from_u128(operation.as_u128()),
                        error: format!("reply waiter capacity exhausted; retained_phase={:?}; no automatic retry", authority.operation(operation).map(|view| view.phase)),
                    });
                    queue_reply(&mut sends, &transport, console, response, &protocol)?;
                    continue;
                }
                let submission = match authority.submit(request.operation(), Uuid::new_v4().as_u128().into()) {
                    Ok(submission) => submission,
                    Err(error @ (StateError::Capacity | StateError::QueueFull | StateError::OperationConflict | StateError::AttemptConflict)) => {
                        let response = Response::new(ResponseMessage::SubmissionError {
                            operation_id: Uuid::from_u128(operation.as_u128()),
                            error: format!("{error}; retained_phase={:?}; no automatic retry", authority.operation(operation).map(|view| view.phase)),
                        });
                        queue_reply(&mut sends, &transport, console, response, &protocol)?;
                        continue;
                    }
                    Err(error) => return Err(error.into()),
                };
                println!("authority accepted: operation={operation} work={} admission={:?}", submission.dispatch.target_instance_id, submission.admission);
                if let Some(report_id) = adopted {
                    let report = authority.report(report_id).context("adopted report is missing")?;
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
                            None => worker.next_report(execute_hello).await?.context("local worker did not produce report")?,
                        };
                        authority.receive_report(report)?;
                        println!("local typed delivery: operation={operation}");
                        continue;
                    }
                    let bytes = Dispatch::from_delivery(&submission.dispatch)?.to_json(&protocol)?;
                    queue_send(&mut sends, &transport, Outgoing {
                        destination: work_inbox(submission.dispatch.target_instance_id),
                        bytes,
                        purpose: SendPurpose::Dispatch(operation),
                    });
                }
            }
            completed = sends.join_next(), if !sends.is_empty() => {
                let (purpose, result) = completed.context("send completion is missing")?.context("send task failed")?;
                match (purpose, result) {
                    (SendPurpose::Dispatch(operation), Ok(())) => {
                        authority.mark_dispatched(operation)?;
                        println!("authority dispatch sent: operation={operation}; work acceptance unknown until evidence");
                    }
                    (SendPurpose::Dispatch(operation), Err(error)) => eprintln!("dispatch not confirmed: operation={operation}; {error}; retained without retry or new authorization"),
                    (SendPurpose::Reply, Err(error)) => eprintln!("console reply not confirmed: {error}; evidence retained without retry"),
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
                .context("adopted report is missing")?;
            response_for(report, waiter.operation)?
        } else {
            authority.mark_wait_timeout(waiter.operation)?;
            println!(
                "authority pending: operation={}; no automatic retry or new authorization",
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
    .context("send timed out; no automatic retry")?
}

/// 启动只执行绑定 Authority 授权的静态 Work 进程
///
/// # 错误
/// 配置, 连接, 接收或内部执行驱动失败时返回错误
pub async fn run_work(
    endpoint: &str,
    instance: NodeInstanceId,
    authority: NodeInstanceId,
) -> Result<()> {
    let inbox = work_inbox(instance);
    let transport = timeout(
        SEND_TIMEOUT,
        Transport::connect(endpoint, &inbox, Limits::default()),
    )
    .await
    .context("connecting work timed out")??;
    serve_worker(transport, instance, authority).await
}

pub(crate) async fn serve_worker(
    transport: Transport,
    instance: NodeInstanceId,
    authority: NodeInstanceId,
) -> Result<()> {
    let mut work = Work::<Task, String, String>::new(
        authority,
        vec![instance],
        beamlet_agent::Limits::default(),
    )?;
    let protocol = ProtocolLimits::default();
    let inbox = work_inbox(instance);
    println!("worker ready: instance={instance} authority={authority}");
    loop {
        let message = tokio::select! {
            received = transport.recv_message() => received.context("receiving work dispatch")?,
            signal = tokio::signal::ctrl_c() => {
                signal?;
                return Ok(());
            }
        };
        ensure!(message.key_expr == inbox, "unexpected work message address");
        let dispatch = match Dispatch::from_json(&message.payload, &protocol) {
            Ok(dispatch) => dispatch.delivery(),
            Err(error) => {
                eprintln!("invalid dispatch, not admitted: {error}");
                continue;
            }
        };
        let cached = match work.receive_dispatch(dispatch) {
            Ok(cached) => cached,
            Err(error) => {
                eprintln!("dispatch not admitted: {error}");
                continue;
            }
        };
        let report = match cached {
            Some(report) => report,
            None => work
                .next_report(execute_hello)
                .await?
                .context("admitted work did not produce a report")?,
        };
        let Message::SubmitReport(evidence) = &report.message else {
            anyhow::bail!("work completion did not contain a report");
        };
        println!(
            "work cached report: operation={} attempt={} report={}",
            evidence.operation_id, evidence.attempt_id, evidence.report_id
        );
        let bytes = hello::encode_report(&report, &protocol)?;
        if let Err(error) = send(&transport, &report_inbox(authority), bytes).await {
            eprintln!("report send not confirmed: {error}; cached without automatic retry");
        }
    }
}

pub(crate) fn work_inbox(instance: NodeInstanceId) -> String {
    format!(
        "beamlet/v0/work/{}/inbox",
        Uuid::from_u128(instance.as_u128()).simple()
    )
}

pub(crate) fn report_inbox(instance: NodeInstanceId) -> String {
    format!(
        "{NODE_INBOX_PREFIX}reports-{}",
        Uuid::from_u128(instance.as_u128()).simple()
    )
}

/// 启动原有的本地 Hello 演示, Authority 与 Work 仍在同一进程
///
/// # 错误
/// 配置, 接纳, 内部驱动或收发出现无法处理的错误时返回错误
pub async fn run_local(endpoint: &str) -> Result<()> {
    let inbox = format!("{NODE_INBOX_PREFIX}*");
    let transport = Transport::listen(endpoint, &inbox, Limits::default())
        .await
        .context("opening node listener")?;
    let authority = Uuid::new_v4().as_u128().into();
    let worker = Uuid::new_v4().as_u128().into();
    let runtime_limits = beamlet_agent::Limits::default();
    let mut agent = HelloAgent::new(authority, vec![worker], runtime_limits)?;
    let protocol_limits = ProtocolLimits::default();
    println!("node listening: {endpoint}");
    println!(
        "volatile authority={authority} work={worker}; retained operation limit={}",
        runtime_limits.max_records
    );

    loop {
        let message = tokio::select! {
            received = transport.recv_message() => received.context("receiving console message")?,
            signal = tokio::signal::ctrl_c() => {
                signal?;
                return Ok(());
            }
        };
        let Some(console_id) = message.key_expr.strip_prefix(NODE_INBOX_PREFIX) else {
            eprintln!("ignored unexpected message address: {:?}", message.key_expr);
            continue;
        };
        // 路由 ID 只用于区分 Console, 不作为认证凭证或任意回复地址
        if console_id.len() != 32 || !console_id.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            eprintln!("ignored invalid console route: {console_id:?}");
            continue;
        }
        let request = match Request::from_json(&message.payload, &protocol_limits) {
            Ok(request) => request,
            Err(error) => {
                eprintln!("invalid request from console[{console_id}], not accepted: {error}");
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
            Ok(Ok(())) => println!("node -> console[{console_id}]: reply sent"),
            Ok(Err(error)) => {
                eprintln!("reply to console[{console_id}] failed, not retried: {error}");
            }
            Err(_) => {
                eprintln!("reply to console[{console_id}] timed out, not retried");
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
            let phase = agent.operation(operation_id).map(|view| view.phase);
            return Ok(Response::new(ResponseMessage::SubmissionError {
                operation_id: Uuid::from_u128(operation_id.as_u128()),
                error: format!("{error}; retained_phase={phase:?}; no automatic retry"),
            }));
        }
        Err(error) => return Err(error.into()),
    };
    let Message::DispatchAttempt(attempt) = &submission.dispatch.message else {
        bail!("agent submission did not retain a dispatch");
    };
    println!(
        "authority: operation={operation_id} attempt={} admission={:?}",
        attempt.attempt_id, submission.admission
    );

    if let Some(report_id) = agent
        .operation(operation_id)
        .and_then(|view| view.adopted_report)
    {
        let retained = agent
            .report(report_id)
            .context("adopted report is missing")?;
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
        bail!("agent completion did not contain a report");
    };
    ensure!(
        report.operation_id == operation,
        "report belongs to another operation"
    );
    println!(
        "authority retained: operation={} attempt={} report={}",
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
        "work executed hello: operation={} attempt={}",
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
