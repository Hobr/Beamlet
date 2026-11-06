//! Console 提交固定 Hello 请求, 按 Operation 身份显示已收录的执行证据

use std::{env, time::Duration};

use anyhow::{Context, Result, bail, ensure};
use beamlet_agent::testing::{
    hello::{Request, Response, ResponseMessage},
    protocol::{ExecutionResult, Limits as ProtocolLimits, Message},
};
use beamlet_message_zenoh::{Limits, Sender, Transport};
use tokio::{
    io::{self, AsyncBufReadExt, AsyncReadExt, BufReader},
    time::timeout,
};
use uuid::Uuid;

const NODE_INBOX: &str = "beamlet/v0/node/inbox";
const ROUND_TRIP_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_LINE_BYTES: usize = 64 * 1024;

#[tokio::main(worker_threads = 2)]
async fn main() -> Result<()> {
    let mut endpoint = String::from("tcp/127.0.0.1:7447");
    let mut authority = None;
    let mut message = None;
    let mut operation_id = None;
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--connect" => endpoint = args.next().context("--connect needs an endpoint")?,
            "--authority" => {
                authority = Some(
                    args.next()
                        .context("--authority needs a UUID")?
                        .parse::<Uuid>()?,
                )
            }
            "--message" => message = Some(args.next().context("--message needs a task")?),
            "--operation-id" => {
                operation_id = Some(
                    args.next()
                        .context("--operation-id needs a UUID")?
                        .parse::<Uuid>()
                        .context("invalid operation UUID")?,
                );
            }
            "--demo" => return Ok(beamlet_agent::testing::demo::print().await?),
            "--help" | "-h" => {
                println!(
                    "beamlet-console [--connect tcp/127.0.0.1:7447] [--authority UUID] [--message hello [--operation-id UUID]] [--demo]"
                );
                return Ok(());
            }
            _ => bail!("unknown argument: {arg}"),
        }
    }

    if operation_id.is_some() && message.is_none() {
        bail!("--operation-id requires --message hello");
    }
    let request = message
        .as_deref()
        .map(|command| hello_request(command, operation_id))
        .transpose()?;

    // 每次启动使用新的路由 ID, 不复用其他 Console 或旧进程的回复地址
    let console_id = Uuid::new_v4().simple().to_string();
    let inbox = format!("beamlet/v0/console/{console_id}/inbox");
    let destination = match authority {
        Some(authority) => format!(
            "beamlet/v0/authority/{}/submit/{console_id}",
            authority.simple()
        ),
        None => format!("{NODE_INBOX}/{console_id}"),
    };
    let transport = timeout(
        ROUND_TRIP_TIMEOUT,
        Transport::connect(&endpoint, &inbox, Limits::default()),
    )
    .await
    .context("connecting to node timed out")?
    .context("connecting to node")?;
    let sender = transport.sender(&destination).await?;
    timeout(ROUND_TRIP_TIMEOUT, sender.wait_for_receiver())
        .await
        .context("node subscriber did not become ready")??;
    println!("console connected: {endpoint} (session {console_id})");

    if let Some(request) = request {
        return exchange(&transport, &sender, &request).await;
    }

    println!("输入 hello 后按 Enter, 每次生成新 Operation; Ctrl-D 退出");
    let mut input = BufReader::new(io::stdin());
    loop {
        let mut bytes = Vec::new();
        let count = (&mut input)
            .take((MAX_LINE_BYTES + 1) as u64)
            .read_until(b'\n', &mut bytes)
            .await?;
        if count == 0 {
            return Ok(());
        }
        if bytes.len() > MAX_LINE_BYTES {
            bail!("input line exceeds {MAX_LINE_BYTES} bytes");
        }
        if bytes.last() == Some(&b'\n') {
            bytes.pop();
            if bytes.last() == Some(&b'\r') {
                bytes.pop();
            }
        }
        let command = String::from_utf8(bytes).context("task name must be UTF-8")?;
        let request = match hello_request(&command, None) {
            Ok(request) => request,
            Err(error) => {
                eprintln!("{error}");
                continue;
            }
        };
        exchange(&transport, &sender, &request).await?;
    }
}

fn hello_request(command: &str, operation_id: Option<Uuid>) -> Result<Request> {
    ensure!(
        command.trim().eq_ignore_ascii_case("hello"),
        "only the fixed hello task is supported; input is no longer echoed"
    );
    Ok(Request::hello(operation_id.unwrap_or_else(Uuid::new_v4)))
}

async fn exchange(transport: &Transport, sender: &Sender<'_>, request: &Request) -> Result<()> {
    let limits = ProtocolLimits::default();
    let bytes = request.to_json(&limits)?;
    println!("operation: {}", request.operation_id());
    timeout(ROUND_TRIP_TIMEOUT, async {
        sender.send(bytes).await?;
        let bytes = transport.recv().await?;
        let response = Response::from_json(&bytes, &limits)?;
        match response.message() {
            ResponseMessage::Report(delivery) => {
                let Message::SubmitReport(report) = &delivery.message else {
                    bail!("response does not contain an execution report");
                };
                ensure!(
                    report.operation_id == request.operation_id(),
                    "received a report for another operation"
                );
                println!("attempt: {}", report.attempt_id);
                println!("report: {}", report.report_id);
                match &report.result {
                    ExecutionResult::Succeeded { output } => {
                        println!("status: succeeded; effect: {:?}", report.effect);
                        println!("output: {output}");
                    }
                    ExecutionResult::Failed { error } | ExecutionResult::Rejected { error } => {
                        bail!(
                            "execution report: {:?}; effect: {:?}; {error}",
                            report.result,
                            report.effect
                        );
                    }
                    _ => bail!("unsupported execution outcome"),
                }
            }
            ResponseMessage::Pending { operation_id } => {
                ensure!(
                    operation_id.as_u128() == request.operation_id().as_u128(),
                    "pending response belongs to another operation"
                );
                println!("status: pending; no automatic retry or new authorization");
            }
            ResponseMessage::SubmissionError {
                operation_id,
                error,
            } => {
                ensure!(
                    operation_id.as_u128() == request.operation_id().as_u128(),
                    "submission response belongs to another operation"
                );
                bail!("submission returned an error, not an execution report: {error}");
            }
            _ => bail!("unsupported response message"),
        }
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("result wait timed out; operation may be retained or executing, no automatic retry")?
}
