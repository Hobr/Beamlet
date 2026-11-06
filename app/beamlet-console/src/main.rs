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
async fn main() -> std::process::ExitCode {
    match run().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("错误: {error:#}");
            std::process::ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<()> {
    let mut endpoint = String::from("tcp/127.0.0.1:7447");
    let mut authority = None;
    let mut message = None;
    let mut operation_id = None;
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--connect" => endpoint = args.next().context("--connect 需要连接地址")?,
            "--authority" => {
                authority = Some(
                    args.next()
                        .context("--authority 需要 UUID")?
                        .parse::<Uuid>()
                        .context("UUID 格式无效")?,
                )
            }
            "--message" => message = Some(args.next().context("--message 需要任务名称")?),
            "--operation-id" => {
                operation_id = Some(
                    args.next()
                        .context("--operation-id 需要 UUID")?
                        .parse::<Uuid>()
                        .context("请求 UUID 无效")?,
                );
            }
            "--demo" => return Ok(beamlet_agent::testing::demo::print().await?),
            "--help" | "-h" => {
                println!(
                    "用法: beamlet-console [--connect tcp/127.0.0.1:7447] [--authority UUID] [--message hello [--operation-id UUID]] [--demo]"
                );
                return Ok(());
            }
            _ => bail!("未知参数: {arg}"),
        }
    }

    if operation_id.is_some() && message.is_none() {
        bail!("--operation-id 必须与 --message hello 一起使用");
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
    .context("连接节点超时")?
    .context("连接节点失败")?;
    let sender = transport.sender(&destination).await?;
    timeout(ROUND_TRIP_TIMEOUT, sender.wait_for_receiver())
        .await
        .context("节点订阅尚未就绪")??;
    println!("控制台已连接: {endpoint} (会话 {console_id})");

    if let Some(request) = request {
        return exchange(&transport, &sender, &request).await;
    }

    println!("输入 hello 后按回车, 每次生成新请求; Ctrl-D 退出");
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
            bail!("输入行超过 {MAX_LINE_BYTES} 字节");
        }
        if bytes.last() == Some(&b'\n') {
            bytes.pop();
            if bytes.last() == Some(&b'\r') {
                bytes.pop();
            }
        }
        let command = String::from_utf8(bytes).context("任务名称必须是 UTF-8 文本")?;
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
        "当前仅支持固定任务 hello, 不再原样回显输入"
    );
    Ok(Request::hello(operation_id.unwrap_or_else(Uuid::new_v4)))
}

async fn exchange(transport: &Transport, sender: &Sender<'_>, request: &Request) -> Result<()> {
    let limits = ProtocolLimits::default();
    let bytes = request.to_json(&limits)?;
    println!("请求: {}", request.operation_id());
    timeout(ROUND_TRIP_TIMEOUT, async {
        sender.send(bytes).await?;
        let bytes = transport.recv().await?;
        let response = Response::from_json(&bytes, &limits)?;
        match response.message() {
            ResponseMessage::Report(delivery) => {
                let Message::SubmitReport(report) = &delivery.message else {
                    bail!("响应不包含执行报告");
                };
                ensure!(
                    report.operation_id == request.operation_id(),
                    "收到其他请求的执行报告"
                );
                println!("执行授权: {}", report.attempt_id);
                println!("执行报告: {}", report.report_id);
                match &report.result {
                    ExecutionResult::Succeeded { output } => {
                        println!("状态: 成功; 外部效果: {}", report.effect);
                        println!("输出: {output}");
                    }
                    ExecutionResult::Failed { error } => {
                        bail!("执行失败; 外部效果: {}; 原因: {error}", report.effect);
                    }
                    ExecutionResult::Rejected { error } => {
                        bail!("执行前拒绝; 外部效果: {}; 原因: {error}", report.effect);
                    }
                    _ => bail!("不支持的执行结果"),
                }
            }
            ResponseMessage::Pending { operation_id } => {
                ensure!(
                    operation_id.as_u128() == request.operation_id().as_u128(),
                    "待定响应属于其他请求"
                );
                println!("状态: 待定; 不自动重试或创建新授权");
            }
            ResponseMessage::SubmissionError {
                operation_id,
                error,
            } => {
                ensure!(
                    operation_id.as_u128() == request.operation_id().as_u128(),
                    "提交响应属于其他请求"
                );
                bail!("提交返回错误, 不是执行报告: {error}");
            }
            _ => bail!("不支持的响应消息"),
        }
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("等待结果超时; 请求可能已保留或正在执行, 不自动重试")?
}
