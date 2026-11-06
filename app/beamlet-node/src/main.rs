//! 静态 Zenoh 节点, 在内存 Agent 内执行 Hello 并返回已收录的 Report

use std::{env, time::Duration};

use anyhow::{Context, Result, bail, ensure};
use beamlet_agent::{
    Agent, AgentError, StateError,
    id::OperationId,
    model::{Delivery, DispatchAttempt, Effect, ExecutionResult, Message, SubmitReport},
    testing::{
        hello::{Request, Response, ResponseMessage, Task},
        protocol::Limits as ProtocolLimits,
    },
};
use beamlet_message_zenoh::{Limits, Transport};
use tokio::time::timeout;
use uuid::Uuid;

type HelloAgent = Agent<Task, String, String>;

const NODE_INBOX_PREFIX: &str = "beamlet/v0/node/inbox/";
const SEND_TIMEOUT: Duration = Duration::from_secs(10);

#[tokio::main(worker_threads = 2)]
async fn main() -> Result<()> {
    let mut endpoint = String::from("tcp/127.0.0.1:7447");
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--listen" => endpoint = args.next().context("--listen needs an endpoint")?,
            "--demo" => return Ok(beamlet_agent::testing::demo::print().await?),
            "--help" | "-h" => {
                println!("beamlet-node [--listen tcp/127.0.0.1:7447] [--demo]");
                return Ok(());
            }
            _ => bail!("unknown argument: {arg}"),
        }
    }

    let inbox = format!("{NODE_INBOX_PREFIX}*");
    let transport = Transport::listen(&endpoint, &inbox, Limits::default())
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
