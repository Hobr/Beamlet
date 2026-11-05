//! 每个 Console 使用独立回复地址的文本往返入口, 不代表执行接纳或持久化

use std::{env, time::Duration};

use anyhow::{Context, Result, bail};
use beamlet_message_zenoh::{Limits, Sender, Transport};
use tokio::{
    io::{self, AsyncBufReadExt, AsyncReadExt, BufReader},
    time::timeout,
};

const NODE_INBOX: &str = "beamlet/v0/node/inbox";
const ROUND_TRIP_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_LINE_BYTES: usize = 64 * 1024;

#[tokio::main(worker_threads = 2)]
async fn main() -> Result<()> {
    let mut endpoint = String::from("tcp/127.0.0.1:7447");
    let mut message = None;
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--connect" => endpoint = args.next().context("--connect needs an endpoint")?,
            "--message" => message = Some(args.next().context("--message needs text")?),
            "--demo" => return Ok(beamlet_agent::testing::demo::print().await?),
            "--help" | "-h" => {
                println!(
                    "beamlet-console [--connect tcp/127.0.0.1:7447] [--message Hello] [--demo]"
                );
                return Ok(());
            }
            _ => bail!("unknown argument: {arg}"),
        }
    }

    // 每次启动使用新的路由 ID, 不复用其他 Console 或旧进程的回复地址
    let console_id = uuid::Uuid::new_v4().simple().to_string();
    let inbox = format!("beamlet/v0/console/{console_id}/inbox");
    let destination = format!("{NODE_INBOX}/{console_id}");
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

    if let Some(message) = message {
        return exchange(&transport, &sender, message.into_bytes()).await;
    }

    println!("输入消息后按 Enter, Ctrl-D 退出");
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
        exchange(&transport, &sender, bytes).await?;
    }
}

async fn exchange(transport: &Transport, sender: &Sender<'_>, bytes: Vec<u8>) -> Result<()> {
    println!("console -> node: {:?}", String::from_utf8_lossy(&bytes));
    timeout(ROUND_TRIP_TIMEOUT, async {
        sender.send(bytes).await?;
        let reply = transport.recv().await?;
        println!("node -> console: {:?}", String::from_utf8_lossy(&reply));
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("reply timed out; delivery and node status are unknown, no automatic retry")?
}
