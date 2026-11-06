//! 静态 Zenoh 节点, 支持本地执行或独立 Authority/Worker 进程

use std::env;

use anyhow::{Context, Result, bail, ensure};
use beamlet_node::roles;
use uuid::Uuid;

#[tokio::main(worker_threads = 2)]
async fn main() -> Result<()> {
    let arguments: Vec<String> = env::args().skip(1).collect();
    if arguments.first().is_some_and(|arg| arg == "--config") {
        ensure!(
            arguments.len() == 2,
            "--config requires exactly one JSON path and cannot be mixed with role flags"
        );
        return beamlet_node::node::run(&arguments[1]).await;
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
            "--listen" => listen = Some(args.next().context("--listen needs an endpoint")?),
            "--connect" => connect = Some(args.next().context("--connect needs an endpoint")?),
            "--role" => {
                role = args
                    .next()
                    .context("--role needs local, authority or worker")?
            }
            "--instance" => {
                instance = Some(
                    args.next()
                        .context("--instance needs a UUID")?
                        .parse::<Uuid>()?,
                );
            }
            "--authority" => {
                authority = Some(
                    args.next()
                        .context("--authority needs a UUID")?
                        .parse::<Uuid>()?,
                );
            }
            "--worker" => {
                workers.push(
                    args.next()
                        .context("--worker needs a UUID")?
                        .parse::<Uuid>()?,
                );
            }
            "--demo" => return Ok(beamlet_agent::testing::demo::print().await?),
            "--help" | "-h" => {
                println!(
                    "beamlet-node --config PATH.json\n\
                     beamlet-node [--role local] [--listen ENDPOINT] [--demo]\n\
                     beamlet-node --role authority --instance UUID --worker UUID [--worker UUID ...] [--listen ENDPOINT]\n\
                     beamlet-node --role worker --instance UUID --authority UUID [--connect ENDPOINT]\n\
                     ENDPOINT defaults to tcp/127.0.0.1:7447; use fresh instance UUIDs for each deployment"
                );
                return Ok(());
            }
            _ => bail!("unknown argument: {arg}"),
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
                "local mode only supports --listen"
            );
            roles::run_local(listen.as_deref().unwrap_or(default_endpoint)).await
        }
        "authority" => {
            ensure!(
                connect.is_none() && authority.is_none(),
                "authority mode does not accept --connect or --authority"
            );
            let instance = instance.context("authority mode requires --instance UUID")?;
            ensure!(
                !workers.contains(&instance),
                "authority and worker instances must differ"
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
                "worker mode does not accept --listen or --worker"
            );
            let instance = instance.context("worker mode requires --instance UUID")?;
            let authority = authority.context("worker mode requires --authority UUID")?;
            ensure!(
                instance != authority,
                "authority and worker instances must differ"
            );
            roles::run_worker(
                connect.as_deref().unwrap_or(default_endpoint),
                instance.as_u128().into(),
                authority.as_u128().into(),
            )
            .await
        }
        _ => bail!("unknown role: {role}"),
    }
}
