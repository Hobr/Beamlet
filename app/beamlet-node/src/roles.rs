//! 静态 Authority/Worker 进程, 只在应用边界交付已有授权和证据

use std::{collections::HashMap, sync::Arc, time::Duration};

use anyhow::{Context, Result, bail, ensure};
use beamlet_agent::{
    Admission, Authority, StateError, Worker,
    id::{OperationId, ReportId, RoleInstanceId},
    model::{Delivery, DispatchAttempt, Effect, ExecutionResult, Message, SubmitReport},
    testing::{
        attempt_receipt::{self, AttemptAccepted},
        hello::{self, Dispatch, Response, ResponseMessage, Task},
        protocol::Limits as ProtocolLimits,
        receipt::{self, ReportRetained},
        submission::{Submission, SubmissionReply},
    },
};
use beamlet_message_zenoh::{Limits, Transport};
use tokio::{
    task::JoinSet,
    time::{Instant, MissedTickBehavior, interval, timeout},
};
use uuid::Uuid;

use crate::{
    attempt_delivery::AttemptDeliveries,
    report_delivery::{ReportDeliveries, SEND_BUDGET},
    shutdown::{self, Shutdown},
};

pub(crate) const NODE_INBOX_PREFIX: &str = "beamlet/v0/node/inbox/";
const SEND_TIMEOUT: Duration = Duration::from_secs(10);

type HelloAuthority = Authority<Task, String, String>;

// 留出 Console 的 10 秒等待预算, 只结束本次观察, 不取消 Worker
const REPLY_WAIT: Duration = Duration::from_secs(5);

struct Waiter {
    operation: OperationId,
    console: String,
    binding: SubmissionReply,
    deadline: Instant,
}

enum SendPurpose {
    Dispatch(OperationId),
    Reply,
    Receipt,
    SubmissionReceipt,
    AttemptReceipt,
    Report(ReportId),
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
    shutdown::standalone(|control| {
        serve_authority_pair(
            transport,
            None,
            AuthoritySetup {
                instance,
                workers,
                local_workers,
                request_prefix,
            },
            control,
        )
    })
    .await
}

pub(crate) struct AuthoritySetup {
    pub instance: RoleInstanceId,
    pub workers: Vec<RoleInstanceId>,
    pub local_workers: HashMap<RoleInstanceId, Worker<Task, String, String>>,
    pub request_prefix: String,
}

pub(crate) async fn serve_authority_pair(
    transport: Arc<Transport>,
    report_transport: Option<Transport>,
    setup: AuthoritySetup,
    mut shutdown: Shutdown,
) -> Result<()> {
    let AuthoritySetup {
        instance,
        workers,
        mut local_workers,
        request_prefix,
    } = setup;
    let limits = beamlet_agent::Limits::default();
    let mut authority = HelloAuthority::new(instance, workers, limits)?;
    let protocol = ProtocolLimits::default();
    let reports = report_inbox(instance);
    let receipt_inbox = attempt_receipt::inbox(instance);
    let receipts = transport.subscribe(&receipt_inbox).await?;
    let mut attempts = AttemptDeliveries::new(limits);
    let mut submissions: HashMap<Uuid, (Submission, SubmissionReply)> = HashMap::new();
    let mut waiters: Vec<Waiter> = Vec::new();
    let mut sends = Sends::new();
    let mut pending = std::collections::HashSet::new();
    let mut draining = false;
    let mut tick = interval(Duration::from_millis(100));
    tick.set_missed_tick_behavior(MissedTickBehavior::Skip);
    println!("Authority 已就绪: 实例={instance}");
    println!(
        "内存记录上限={}; 等待回复与发送任务各自上限={}",
        limits.max_records, limits.queue_capacity
    );

    loop {
        if shutdown.is_draining() && !draining {
            draining = true;
            println!(
                "Authority 进入 Draining: 实例={instance}; 未报告 Operation={}",
                pending.len()
            );
        }
        flush_replies(
            &mut authority,
            &mut waiters,
            &mut sends,
            &transport,
            &protocol,
            limits.queue_capacity,
        )?;
        while sends.len() < limits.queue_capacity {
            let Some((operation, destination, bytes)) = attempts.next_send() else {
                break;
            };
            queue_send(
                &mut sends,
                &transport,
                Outgoing {
                    destination,
                    bytes,
                    purpose: SendPurpose::Dispatch(operation),
                },
            );
        }
        tokio::select! {
            _ = shutdown.requested(), if !draining => {}
            received = receipts.recv_message() => {
                match received {
                    Ok(message) => {
                        let result = (|| {
                            let receipt = AttemptAccepted::from_json(&message.payload)?;
                            ensure!(message.key_expr == receipt_inbox && message.key_expr == receipt.topic(), "Attempt 回执实际路由不符");
                            if attempts.acknowledge(&receipt)? {
                                println!("Authority 已确认 Worker 接纳: Operation={} Attempt={}; 不表示执行已开始或完成", receipt.operation_id, receipt.attempt_id);
                            }
                            Ok::<_,anyhow::Error>(())
                        })();
                        if let Err(error) = result { eprintln!("已忽略 Attempt 接纳回执: {error}"); }
                    }
                    Err(error @ (beamlet_message_zenoh::Error::UnexpectedDelete | beamlet_message_zenoh::Error::MessageTooLarge)) => eprintln!("已忽略 Attempt 接纳回执: {error}"),
                    Err(error) => return Err(error).context("接收 Attempt 回执失败"),
                }
            }
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
                let message = match received {
                    Ok(message) => message,
                    Err(error @ (beamlet_message_zenoh::Error::UnexpectedDelete | beamlet_message_zenoh::Error::MessageTooLarge)) => { eprintln!("已忽略非法提交或 Report: {error}"); continue; }
                    Err(error) => return Err(error).context("Authority 接收消息失败"),
                };
                if message.key_expr == reports {
                    let delivery = match hello::decode_report(&message.payload, &protocol) {
                        Ok(delivery) => delivery,
                        Err(error) => {
                            eprintln!("已忽略无效 Report: {error}");
                            continue;
                        }
                    };
                    let operation = match &delivery.message {
                        Message::SubmitReport(report) => report.operation_id,
                        _ => unreachable!("Report 解码只能返回 Report"),
                    };
                    let receipt = ReportRetained::for_report(&delivery)?;
                    match authority.receive_report(delivery) {
                        Ok(disposition) => {
                            pending.remove(&operation);
                            attempts.reported(operation);
                            println!("Authority 已接收 Report: {disposition}; 停止原授权重投");
                            if sends.len() < limits.queue_capacity {
                                queue_send(&mut sends, &transport, Outgoing {
                                    destination: receipt.topic(),
                                    bytes: receipt.to_json()?,
                                    purpose: SendPurpose::Receipt,
                                });
                            } else {
                                eprintln!("Report 已收录, 回执发送槽位已满: Report={}; 等待原证据重投, 不回滚收录", receipt.report_id);
                            }
                        },
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
                let request = match Submission::from_json(&message.payload, &protocol) {
                    Ok(request) => request,
                    Err(error) => {
                        eprintln!("提交无效, 本次未处理: {error}");
                        continue;
                    }
                };
                if sends.len() + 2 > limits.queue_capacity {
                    eprintln!("提交发送槽位已满; 本次未处理, 不创建身份");
                    continue;
                }
                let key = request.submission_key;
                let existing = submissions.get(&key);
                let rejection = if let Some((retained, _)) = existing {
                    (retained != &request).then_some("SubmissionKey 与已保留定义冲突")
                } else if shutdown.is_draining() {
                    Some("NodeShutdown: 新提交未接纳")
                } else if submissions.len() >= limits.max_records || !attempts.has_capacity() {
                    Some("提交记录或 Attempt 交付槽位已满; 新提交未接纳")
                } else { None };
                if let Some(error) = rejection {
                    queue_submission(&mut sends, &transport, console, SubmissionReply::rejected(key, Uuid::from_u128(instance.as_u128()), error.to_owned()), &protocol)?;
                    continue;
                }
                let operation = existing.map(|(_,binding)| binding.operation_id.expect("接纳映射必须包含 Operation"))
                    .unwrap_or_else(Uuid::new_v4);
                let operation = beamlet_agent::id::OperationId::from_u128(operation.as_u128());
                let adopted = authority.operation(operation).and_then(|view| view.adopted_report);
                let already_waiting = waiters.iter().any(|waiter| waiter.operation == operation && waiter.console == console);
                if adopted.is_none() && !already_waiting && waiters.len() >= limits.queue_capacity {
                    if let Some((_, binding)) = existing {
                        queue_submission(&mut sends, &transport, console, binding.clone(), &protocol)?;
                        queue_reply(&mut sends, &transport, console, binding, Response::new(ResponseMessage::Pending { operation_id: Uuid::from_u128(operation.as_u128()) }), &protocol)?;
                    } else {
                        queue_submission(&mut sends, &transport, console, SubmissionReply::rejected(key, Uuid::from_u128(instance.as_u128()), "等待回复记录已满; 新提交未接纳".to_owned()), &protocol)?;
                    }
                    continue;
                }
                let submission = match authority.submit(request.operation(Uuid::from_u128(operation.as_u128())), Uuid::new_v4().as_u128().into()) {
                    Ok(submission) => submission,
                    Err(error @ (StateError::Capacity | StateError::QueueFull | StateError::OperationConflict | StateError::AttemptConflict)) => {
                        queue_submission(&mut sends, &transport, console, SubmissionReply::rejected(key, Uuid::from_u128(instance.as_u128()), error.to_string()), &protocol)?;
                        continue;
                    }
                    Err(error) => return Err(error.into()),
                };
                let Message::DispatchAttempt(dispatch) = &submission.dispatch.message else { bail!("接纳结果缺少 Attempt"); };
                let binding = SubmissionReply::accepted(key, Uuid::from_u128(instance.as_u128()), Uuid::from_u128(operation.as_u128()), Uuid::from_u128(dispatch.attempt_id.as_u128()));
                // 单一驱动同步完成映射和接纳, 在发布回执或执行前没有 await
                submissions.entry(key).or_insert_with(|| (request, binding.clone()));
                queue_submission(&mut sends, &transport, console, binding.clone(), &protocol)?;
                println!("Authority 已接纳: SubmissionKey={key} Operation={operation} Worker={} 接纳结果={}", submission.dispatch.target_instance_id, submission.admission);
                if let Some(report_id) = adopted {
                    let report = authority.report(report_id).context("已采用的 Report 缺失")?;
                    queue_reply(&mut sends, &transport, console, &binding, response_for(report, operation)?, &protocol)?;
                    continue;
                }
                if !already_waiting {
                    waiters.push(Waiter { operation, console: console.to_owned(), binding, deadline: Instant::now() + REPLY_WAIT });
                }
                if submission.admission == Admission::New {
                    pending.insert(operation);
                    if let Some(worker) = local_workers.get_mut(&submission.dispatch.target_instance_id) {
                        let cached = worker.receive_dispatch(submission.dispatch.clone())?;
                        println!("本地 Attempt 接纳已确认: Operation={operation}; 类型化返回, 不表示执行完成");
                        authority.mark_dispatched(operation)?;
                        let report = match cached {
                            Some(report) => report,
                            None => worker.next_report(execute_hello).await?.context("本地 Worker 未产生 Report")?,
                        };
                        let receipt = ReportRetained::for_report(&report)?;
                        authority.receive_report(report)?;
                        println!("本地 Report 收录已确认: Report={}; 类型化返回, 不走网络回执, 不表示持久化", receipt.report_id);
                        pending.remove(&operation);
                        println!("本地类型化交付: Operation={operation}");
                        continue;
                    }
                    attempts.retain(&submission.dispatch, &protocol)?;
                }
            }
            completed = sends.join_next(), if !sends.is_empty() => {
                let (purpose, result) = completed.context("发送完成记录缺失")?.context("发送任务失败")?;
                match (purpose, result) {
                    (SendPurpose::Dispatch(operation), Ok(())) => {
                        attempts.sent(operation);
                        authority.mark_dispatched(operation)?;
                        println!("Authority 已发出授权: Operation={operation}; 本次发送完成本身不证明 Worker 接纳");
                    }
                    (SendPurpose::Dispatch(operation), Err(error)) => {
                        attempts.sent(operation);
                        eprintln!("授权本次发送未确认: Operation={operation}; {error}; 仅在原预算内重投, 不创建新授权");
                    },
                    (SendPurpose::Reply, Err(error)) => eprintln!("Console 回复未确认: {error}; 证据已保留, 不重试"),
                    (SendPurpose::Reply, Ok(())) => {}
                    (SendPurpose::Receipt, Ok(())) => println!("Report 收录回执已发出; 不等待回执的回执, 不表示持久化"),
                    (SendPurpose::Receipt, Err(error)) => eprintln!("Report 收录回执发送未确认: {error}; 原证据仍已保留, 合法重复可再次回复"),
                    (SendPurpose::SubmissionReceipt, Err(error)) => eprintln!("Operation 回执发送未确认: {error}; 接纳映射保留, 原 key 重投可再次回复"),
                    (SendPurpose::SubmissionReceipt, Ok(())) => {},
                    (SendPurpose::AttemptReceipt, _) => bail!("Authority 不应发送 Attempt 接纳回执"),
                    (SendPurpose::Report(_), _) => bail!("Authority 不应包含 Worker Report 发送任务"),
                }
            }
            _ = tick.tick() => {
                if draining && pending.is_empty() && waiters.is_empty() && sends.is_empty() {
                    println!("Authority Draining 完成: 实例={instance}; 已接纳 Operation 均已有 Report, 发送尝试已结束; 不保证跨重启保留");
                    return Ok(());
                }
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
        queue_reply(
            sends,
            transport,
            &waiter.console,
            &waiter.binding,
            response,
            protocol,
        )?;
    }
    Ok(())
}

fn queue_reply(
    sends: &mut Sends,
    transport: &Arc<Transport>,
    console: &str,
    binding: &SubmissionReply,
    response: Response,
    protocol: &ProtocolLimits,
) -> Result<()> {
    queue_submission(
        sends,
        transport,
        console,
        binding.with_response(response),
        protocol,
    )
}

fn queue_submission(
    sends: &mut Sends,
    transport: &Arc<Transport>,
    console: &str,
    reply: SubmissionReply,
    protocol: &ProtocolLimits,
) -> Result<()> {
    queue_send(
        sends,
        transport,
        Outgoing {
            destination: format!("beamlet/v0/console/{console}/inbox"),
            bytes: reply.to_json(protocol)?,
            purpose: if reply.response.is_none() {
                SendPurpose::SubmissionReceipt
            } else {
                SendPurpose::Reply
            },
        },
    );
    Ok(())
}

fn queue_send(sends: &mut Sends, transport: &Arc<Transport>, outgoing: Outgoing) {
    // 有界发送任务共享同一会话, 不持有 Authority 状态或锁
    let transport = Arc::clone(transport);
    sends.spawn(async move {
        let budget = match &outgoing.purpose {
            SendPurpose::SubmissionReceipt
            | SendPurpose::Receipt
            | SendPurpose::AttemptReceipt
            | SendPurpose::Dispatch(_)
            | SendPurpose::Report(_) => SEND_BUDGET,
            _ => SEND_TIMEOUT,
        };
        let result = send(&transport, &outgoing.destination, outgoing.bytes, budget).await;
        (outgoing.purpose, result)
    });
}

async fn send(
    transport: &Transport,
    destination: &str,
    bytes: Vec<u8>,
    budget: Duration,
) -> Result<()> {
    timeout(budget, async {
        let sender = transport.sender(destination).await?;
        sender.wait_for_receiver().await?;
        sender.send(bytes).await?;
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("消息发送超时")?
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
    let receipts = transport.subscribe(&receipt::inbox(instance)).await?;
    shutdown::standalone(|control| serve_worker(transport, receipts, instance, authority, control))
        .await
}

pub(crate) async fn serve_worker(
    transport: Transport,
    receipts: Transport,
    instance: RoleInstanceId,
    authority: RoleInstanceId,
    mut shutdown: Shutdown,
) -> Result<()> {
    let limits = beamlet_agent::Limits::default();
    let mut worker = Worker::<Task, String, String>::new(authority, vec![instance], limits)?;
    let transport = Arc::new(transport);
    let protocol = ProtocolLimits::default();
    let inbox = worker_inbox(instance);
    let receipt_inbox = receipt::inbox(instance);
    let mut deliveries = ReportDeliveries::new(limits);
    let mut sends = Sends::new();
    let mut draining = false;
    let mut tick = interval(Duration::from_millis(100));
    tick.set_missed_tick_behavior(MissedTickBehavior::Skip);
    println!("Worker 已就绪: 实例={instance} Authority={authority}");
    loop {
        if shutdown.is_draining() && !draining {
            draining = true;
            println!(
                "Worker 进入 Draining: 实例={instance}; 已接纳未完成 Attempt={}; 未确认 Report={}",
                worker.pending(),
                deliveries.unconfirmed()
            );
        }
        deliveries.refresh();
        while sends.len() < limits.queue_capacity {
            let Some((report, bytes)) = deliveries.next_send() else {
                break;
            };
            queue_send(
                &mut sends,
                &transport,
                Outgoing {
                    destination: report_inbox(authority),
                    bytes,
                    purpose: SendPurpose::Report(report),
                },
            );
        }
        tokio::select! {
            biased;
            _ = shutdown.requested(), if !draining => {}
            completed = sends.join_next(), if !sends.is_empty() => {
                let (purpose, result) = completed.context("Report 发送完成记录缺失")?.context("Report 发送任务失败")?;
                match purpose {
                    SendPurpose::Report(report) => {
                        deliveries.sent(report);
                        if let Err(error) = result { eprintln!("Report 本次发送未确认: Report={report}; {error}; 仅在原交付预算内重投, 不重跑"); }
                    }
                    SendPurpose::AttemptReceipt => {
                        if let Err(error) = result { eprintln!("Attempt 回执发送未确认: {error}; 合法重复授权可再次回复"); }
                    }
                    _ => bail!("Worker 发送任务种类错误"),
                }
            }
            completed = worker.next_report(execute_hello), if worker.pending() > 0 && sends.len() < limits.queue_capacity => {
                let report = completed?.context("Worker 完成记录缺失")?;
                let Message::SubmitReport(evidence) = &report.message else { bail!("Worker 完成结果不包含 Report"); };
                println!("Worker 已缓存 Report: Operation={} Attempt={} Report={}", evidence.operation_id, evidence.attempt_id, evidence.report_id);
                deliveries.retain(&report, &protocol)?;
            }
            _ = tick.tick() => {
                if draining && worker.pending() == 0 && deliveries.unconfirmed() == 0 && sends.is_empty() {
                    println!("Worker Draining 完成: 实例={instance}; Report 均已获得 Authority 收录回执, 发送尝试已结束; 不保证跨重启保留");
                    return Ok(());
                }
            }
            received = receipts.recv_message() => {
                match received {
                    Ok(message) => {
                        let result = (|| {
                            let receipt = ReportRetained::from_json(&message.payload)?;
                            ensure!(message.key_expr == receipt_inbox && message.key_expr == receipt.topic(), "Report 收录回执实际路由不符");
                            if deliveries.acknowledge(&receipt)? {
                                println!("Worker 已确认 Authority 收录 Report: Operation={} Attempt={} Report={}; 不表示已采用或持久化", receipt.operation_id, receipt.attempt_id, receipt.report_id);
                            }
                            Ok::<_, anyhow::Error>(())
                        })();
                        if let Err(error) = result { eprintln!("已忽略 Report 收录回执: {error}"); }
                    }
                    Err(error @ (beamlet_message_zenoh::Error::UnexpectedDelete | beamlet_message_zenoh::Error::MessageTooLarge)) => eprintln!("已忽略 Report 收录回执: {error}"),
                    Err(error) => return Err(error).context("接收 Report 收录回执失败"),
                }
            }
            received = transport.recv_message() => {
                let message = received.context("Worker 接收授权失败")?;
                ensure!(message.key_expr == inbox, "Worker 消息地址与预期不符");
                let dispatch = match Dispatch::from_json(&message.payload, &protocol) {
                    Ok(dispatch) => dispatch.delivery(),
                    Err(error) => { eprintln!("授权无效, 未接纳: {error}"); continue; }
                };
                match worker.retained_dispatch(&dispatch) {
                    Err(error) => { eprintln!("授权未接纳: {error}"); continue; }
                    Ok(None) if shutdown.is_draining() => {
                        eprintln!("NodeShutdown: Worker 处于 Draining; 新 Attempt 未接纳, 不生成 Report");
                        continue;
                    }
                    Ok(None) if !deliveries.has_capacity(worker.pending()) => {
                        eprintln!("Worker 执行或活动 Report 交付槽位已满; 本次新 Attempt 未入队");
                        continue;
                    }
                    _ => {}
                }
                let receipt = AttemptAccepted::for_dispatch(&dispatch)?;
                match worker.receive_dispatch(dispatch) {
                    Ok(report) => {
                        if let Some(report) = report { deliveries.retain(&report, &protocol)?; }
                        if sends.len() < limits.queue_capacity {
                            queue_send(&mut sends, &transport, Outgoing {
                                destination: receipt.topic(), bytes: receipt.to_json()?, purpose: SendPurpose::AttemptReceipt,
                            });
                        } else { eprintln!("Attempt 已接纳, 回执发送槽位已满; 不回滚接纳"); }
                    }
                    Err(error) => eprintln!("授权未接纳: {error}"),
                }
            }
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
