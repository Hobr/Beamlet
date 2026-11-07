//! Console 提交固定 Hello 请求, 按 Operation 身份显示已收录的执行证据

use std::{env, time::Duration};

use anyhow::{Context, Result, bail, ensure};
use beamlet_agent::testing::{
    hello::ResponseMessage,
    protocol::{ExecutionResult, Limits as ProtocolLimits, Message},
    submission::{Submission, SubmissionReply},
};
use beamlet_message_zenoh::{Limits, Sender, Transport};
use tokio::{
    io::{self, AsyncBufReadExt, AsyncReadExt, BufReader},
    time::timeout,
};
use uuid::Uuid;

mod notifications;
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
    let mut submission_key = None;
    let mut subscribe = false;
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
            "--submission-key" => {
                submission_key = Some(
                    args.next()
                        .context("--submission-key 需要 UUID")?
                        .parse::<Uuid>()
                        .context("SubmissionKey UUID 无效")?,
                );
            }
            "--subscribe" => subscribe = true,
            "--demo" => return Ok(beamlet_agent::testing::demo::print().await?),
            "--help" | "-h" => {
                println!(
                    "用法: beamlet-console [--connect tcp/127.0.0.1:7447] [--authority UUID] [--subscribe] [--message hello [--submission-key UUID]] [--demo]\n--subscribe 启用只读角色启动/退出通知; 输入结束后继续订阅, Ctrl-C 退出"
                );
                return Ok(());
            }
            _ => bail!("未知参数: {arg}"),
        }
    }

    if submission_key.is_some() && message.is_none() {
        bail!("--submission-key 必须与 --message hello 一起使用");
    }
    let request = message
        .as_deref()
        .map(|command| hello_request(command, submission_key))
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
    .context("连接 Node 超时")?
    .context("连接 Node 失败")?;
    let subscription = if subscribe {
        Some(
            transport
                .subscribe(beamlet_agent::testing::lifecycle::SUBSCRIPTION)
                .await?,
        )
    } else {
        None
    };
    let sender = transport.sender(&destination).await?;
    if !subscribe {
        timeout(ROUND_TRIP_TIMEOUT, sender.wait_for_receiver())
            .await
            .context("Node 订阅尚未就绪")??;
    }
    println!("Console 已连接: {endpoint} (会话 {console_id})");
    let business = async {
        if let Some(request) = request {
            return exchange(&transport, &sender, &request, authority).await;
        }
        interactive(&transport, &sender, authority).await?;
        if subscribe {
            std::future::pending::<Result<()>>().await
        } else {
            Ok(())
        }
    };
    if let Some(subscription) = subscription {
        println!("Client 已启用生命周期订阅; 不发布 Client 生命周期通知");
        tokio::select! {
            result = business => result,
            result = notifications::receive(subscription) => result,
            signal = tokio::signal::ctrl_c() => { signal?; Ok(()) }
        }
    } else {
        business.await
    }
}

async fn interactive(
    transport: &Transport,
    sender: &Sender<'_>,
    authority: Option<Uuid>,
) -> Result<()> {
    println!("输入 hello 后按回车, 每次生成新 Operation; Ctrl-D 结束输入");
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
        exchange(transport, sender, &request, authority).await?;
    }
}

fn hello_request(command: &str, submission_key: Option<Uuid>) -> Result<Submission> {
    ensure!(
        command.trim().eq_ignore_ascii_case("hello"),
        "当前仅支持固定任务 hello, 不再原样回显输入"
    );
    Ok(Submission::hello(
        submission_key.unwrap_or_else(Uuid::new_v4),
    ))
}

async fn exchange(
    transport: &Transport,
    sender: &Sender<'_>,
    request: &Submission,
    expected_authority: Option<Uuid>,
) -> Result<()> {
    let limits = ProtocolLimits::default();
    let bytes = request.to_json(&limits)?;
    println!("SubmissionKey: {}", request.submission_key);
    timeout(ROUND_TRIP_TIMEOUT, async {
        let mut attempts = 0;
        let mut next = tokio::time::Instant::now();
        let mut binding = None;
        loop {
            tokio::select! {
                _ = tokio::time::sleep_until(next), if binding.is_none() && attempts < 3 => {
                    attempts += 1;
                    println!("提交尝试: 次数={attempts}/3; 使用原 SubmissionKey");
                    let sent = timeout(Duration::from_millis(500), async {
                        sender.wait_for_receiver().await?;
                        sender.send(bytes.clone()).await
                    }).await;
                    if !matches!(sent, Ok(Ok(()))) { eprintln!("提交本次发送未确认; 使用原 SubmissionKey, 尝试次数={attempts}/3"); }
                    next = tokio::time::Instant::now() + Duration::from_secs(1);
                }
                received = transport.recv() => {
                    let bytes = match received {
                        Ok(bytes) => bytes,
                        Err(error @ (beamlet_message_zenoh::Error::UnexpectedDelete | beamlet_message_zenoh::Error::MessageTooLarge)) => { eprintln!("已忽略非法提交回复: {error}"); continue; }
                        Err(error) => return Err(error.into()),
                    };
                    let reply = match SubmissionReply::from_json(&bytes, &limits) {
                        Ok(reply) => reply,
                        Err(error) => { eprintln!("已忽略非法提交回复: {error}"); continue; }
                    };
                    if reply.submission_key != request.submission_key || expected_authority.is_some_and(|id| id != reply.authority_instance_id) {
                        eprintln!("已忽略其他提交或 Authority 的回复"); continue;
                    }
                    if let Some(error) = reply.error { bail!("提交返回错误, 不是 Report: {error}"); }
                    let current = (reply.authority_instance_id, reply.operation_id.context("接纳缺少 Operation")?, reply.attempt_id.context("接纳缺少 Attempt")?);
                    if let Some(previous) = binding {
                        if previous != current { eprintln!("已忽略与原接纳映射冲突的回复"); continue; }
                    } else {
                        binding = Some(current);
                        println!("Operation: {}", current.1);
                        println!("Attempt: {}", current.2);
                        println!("状态: 已接纳; Authority={}; 不代表开始执行或完成", current.0);
                    }
                    let Some(response) = reply.response else { continue; };
                    match response.message() {
                        ResponseMessage::Report(delivery) => {
                            let Message::SubmitReport(report) = &delivery.message else { bail!("响应不包含 Report"); };
                            println!("Report: {}", report.report_id);
                            match &report.result {
                                ExecutionResult::Succeeded { output } => { println!("状态: 成功; Effect: {}", report.effect); println!("输出: {output}"); }
                                ExecutionResult::Failed { error } => bail!("执行失败; Effect: {}; 原因: {error}", report.effect),
                                ExecutionResult::Rejected { error } => bail!("执行前拒绝; Effect: {}; 原因: {error}", report.effect),
                                _ => bail!("不支持的执行结果"),
                            }
                        }
                        ResponseMessage::Pending { .. } => println!("状态: 待定; 不创建新授权"),
                        ResponseMessage::SubmissionError { error, .. } => bail!("提交返回错误, 不是 Report: {error}"),
                        _ => bail!("不支持的响应消息"),
                    }
                    return Ok::<_,anyhow::Error>(());
                }
            }
        }
    }).await.context("等待结果超时; 提交可能已接纳或正在执行, 重投预算不再延长; 查询须复用原 SubmissionKey")?
}
