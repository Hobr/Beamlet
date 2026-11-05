//! 静态 Zenoh 节点, 接收 Console 字节并原样回复, 尚不执行 Operation

use std::{env, time::Duration};

use anyhow::{Context, Result, bail};
use beamlet_message_zenoh::{Limits, Transport};
use tokio::time::timeout;

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
    println!("node listening: {endpoint}");

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
        println!(
            "console[{console_id}] -> node: {:?}",
            String::from_utf8_lossy(&message.payload)
        );
        let destination = format!("beamlet/v0/console/{console_id}/inbox");
        let outcome = timeout(SEND_TIMEOUT, async {
            let reply = transport.sender(&destination).await?;
            reply.wait_for_receiver().await?;
            reply.send(message.payload).await
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
