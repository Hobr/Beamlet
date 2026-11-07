//! 静态 Zenoh 节点, 支持本地执行或独立 Authority/Worker 进程

use std::env;

use anyhow::{Context, Result, bail, ensure};
use beamlet_node::roles;
use uuid::Uuid;

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
    let arguments: Vec<String> = env::args().skip(1).collect();
    if arguments.first().is_some_and(|arg| arg == "--config") {
        ensure!(
            arguments.len() == 2,
            "--config 需要且仅接受一个 JSON 路径, 不能与角色参数混用"
        );
        return beamlet_node::node::run(Some(&arguments[1]), None).await;
    }
    let mut listen = None;
    let mut connect = None;
    let mut role = String::from("local");
    let mut instance = None;
    let mut authority = None;
    let mut workers = Vec::new();
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--listen" => listen = Some(args.next().context("--listen 需要监听地址")?),
            "--connect" => connect = Some(args.next().context("--connect 需要连接地址")?),
            "--role" => {
                role = args
                    .next()
                    .context("--role 需要 local, authority 或 worker")?
            }
            "--instance" => {
                instance = Some(
                    args.next()
                        .context("--instance 需要 UUID")?
                        .parse::<Uuid>()
                        .context("UUID 格式无效")?,
                );
            }
            "--authority" => {
                authority = Some(
                    args.next()
                        .context("--authority 需要 UUID")?
                        .parse::<Uuid>()
                        .context("UUID 格式无效")?,
                );
            }
            "--worker" => {
                workers.push(
                    args.next()
                        .context("--worker 需要 UUID")?
                        .parse::<Uuid>()
                        .context("UUID 格式无效")?,
                );
            }
            "--demo" => return Ok(beamlet_agent::testing::demo::print().await?),
            "--help" | "-h" => {
                println!(
                    "用法:\n\
                     beamlet-node --config PATH.json\n\
                     beamlet-node [--role local] [--listen ENDPOINT] [--demo]\n\
                     beamlet-node --role authority --instance UUID --worker UUID [--worker UUID ...] [--listen ENDPOINT]\n\
                     beamlet-node --role worker --instance UUID --authority UUID [--connect ENDPOINT]\n\
                     ENDPOINT 为连接或监听地址, 默认为 tcp/127.0.0.1:7447; PATH.json 为配置文件路径. 每轮部署必须使用新的实例 UUID\n\
                     未指定配置或独立角色时使用默认配置: 1 个 Authority, 1 个 Worker; --role local 仅为兼容参数\n\
                     默认配置支持 --listen 和角色生命周期通知; 逻辑身份随机生成, 不跨启动保留"
                );
                return Ok(());
            }
            _ => bail!("未知参数: {arg}"),
        }
    }

    let default_endpoint = "tcp/127.0.0.1:7447";
    match role.as_str() {
        "local" => {
            ensure!(
                connect.is_none()
                    && instance.is_none()
                    && authority.is_none()
                    && workers.is_empty(),
                "本地模式仅支持 --listen"
            );
            beamlet_node::node::run(None, listen.as_deref()).await
        }
        "authority" => {
            ensure!(
                connect.is_none() && authority.is_none(),
                "Authority 模式不接受 --connect 或 --authority"
            );
            let instance = instance.context("Authority 模式需要 --instance UUID")?;
            ensure!(
                !workers.contains(&instance),
                "Authority 与 Worker 的实例身份必须不同"
            );
            roles::run_authority(
                listen.as_deref().unwrap_or(default_endpoint),
                instance.as_u128().into(),
                workers.into_iter().map(|id| id.as_u128().into()).collect(),
            )
            .await
        }
        "worker" => {
            ensure!(
                listen.is_none() && workers.is_empty(),
                "Worker 模式不接受 --listen 或 --worker"
            );
            let instance = instance.context("Worker 模式需要 --instance UUID")?;
            let authority = authority.context("Worker 模式需要 --authority UUID")?;
            ensure!(
                instance != authority,
                "Authority 与 Worker 的实例身份必须不同"
            );
            roles::run_worker(
                connect.as_deref().unwrap_or(default_endpoint),
                instance.as_u128().into(),
                authority.as_u128().into(),
            )
            .await
        }
        _ => bail!("未知角色: {role}"),
    }
}
