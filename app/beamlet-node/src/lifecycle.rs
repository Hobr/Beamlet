//! 配置模式的 Worker 启动公告, 只记录实例绑定, 不授予执行权或在线资格

use std::{collections::HashMap, time::Duration};

use anyhow::{Context, Result, ensure};
use beamlet_message_zenoh::Transport;
use serde::{Deserialize, Serialize};
use tokio::time::timeout;
use uuid::Uuid;

pub(crate) const MAX_WORKERS: usize = 64;
const MAX_ANNOUNCEMENT_BYTES: usize = 4096;
const ANNOUNCE_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum Kind {
    WorkerStarted,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Announcement {
    protocol_version: u8,
    kind: Kind,
    node_id: Uuid,
    node_instance_id: Uuid,
    worker_id: Uuid,
    worker_instance_id: Uuid,
    authority_instance_id: Uuid,
}

impl Announcement {
    pub(crate) fn started(
        node_id: Uuid,
        node_instance_id: Uuid,
        worker_id: Uuid,
        worker_instance_id: Uuid,
        authority_instance_id: Uuid,
    ) -> Self {
        Self {
            protocol_version: 0,
            kind: Kind::WorkerStarted,
            node_id,
            node_instance_id,
            worker_id,
            worker_instance_id,
            authority_instance_id,
        }
    }

    fn from_json(bytes: &[u8]) -> Result<Self> {
        ensure!(
            bytes.len() <= MAX_ANNOUNCEMENT_BYTES,
            "Worker 公告超过字节上限"
        );
        let announcement: Self = serde_json::from_slice(bytes).context("Worker 公告格式无效")?;
        ensure!(announcement.protocol_version == 0, "Worker 公告版本不支持");
        Ok(announcement)
    }
}

pub(crate) fn inbox(authority: Uuid) -> String {
    format!(
        "beamlet/v0/authority/{}/lifecycle/worker/*",
        authority.simple()
    )
}

fn destination(authority: Uuid, worker: Uuid) -> String {
    format!(
        "beamlet/v0/authority/{}/lifecycle/worker/{}",
        authority.simple(),
        worker.simple()
    )
}

#[derive(Debug)]
pub(crate) struct Observations {
    authority: Uuid,
    workers: HashMap<Uuid, Option<Announcement>>,
}

impl Observations {
    pub(crate) fn new(authority: Uuid, workers: &[Uuid]) -> Result<Self> {
        ensure!(workers.len() <= MAX_WORKERS, "Worker 公告观察数量超过上限");
        let entries: HashMap<_, _> = workers.iter().map(|worker| (*worker, None)).collect();
        ensure!(entries.len() == workers.len(), "Worker 公告观察实例重复");
        Ok(Self {
            authority,
            workers: entries,
        })
    }

    pub(crate) fn record(&mut self, announcement: Announcement) -> Result<()> {
        ensure!(
            announcement.authority_instance_id == self.authority,
            "Worker 公告属于其他 Authority 实例"
        );
        let retained = self
            .workers
            .get_mut(&announcement.worker_instance_id)
            .context("Worker 公告实例不在配置列表中")?;
        if let Some(previous) = retained {
            ensure!(
                previous == &announcement,
                "Worker 公告与已保留的实例归属冲突"
            );
            println!(
                "Authority 重复公告: 实例={} Worker 实例={}; 保留原记录",
                self.authority, announcement.worker_instance_id
            );
            return Ok(());
        }
        println!(
            "Authority 已记录 Worker 启动公告: 实例={} WorkerId={} WorkerInstanceId={} NodeId={} NodeInstanceId={}; 仅为观察, 不表示在线或执行接纳",
            self.authority,
            announcement.worker_id,
            announcement.worker_instance_id,
            announcement.node_id,
            announcement.node_instance_id
        );
        *retained = Some(announcement);
        Ok(())
    }

    pub(crate) async fn serve(mut self, transport: Transport) -> Result<()> {
        loop {
            let message = match transport.recv_message().await {
                Ok(message) => message,
                Err(
                    error @ (beamlet_message_zenoh::Error::MessageTooLarge
                    | beamlet_message_zenoh::Error::UnexpectedDelete),
                ) => {
                    eprintln!("已忽略 Worker 公告: {error}");
                    continue;
                }
                Err(error) => return Err(error).context("接收 Worker 公告失败"),
            };
            let result = (|| {
                let announcement = Announcement::from_json(&message.payload)?;
                ensure!(
                    message.key_expr
                        == destination(self.authority, announcement.worker_instance_id),
                    "Worker 公告路由与实例绑定不符"
                );
                self.record(announcement)
            })();
            if let Err(error) = result {
                eprintln!("已忽略 Worker 公告: {error}");
            }
        }
    }
}

pub(crate) async fn announce(transport: &Transport, announcement: Announcement) {
    let result = timeout(ANNOUNCE_TIMEOUT, async {
        let bytes = serde_json::to_vec(&announcement)?;
        ensure!(
            bytes.len() <= MAX_ANNOUNCEMENT_BYTES,
            "Worker 公告超过字节上限"
        );
        let sender = transport
            .sender(&destination(
                announcement.authority_instance_id,
                announcement.worker_instance_id,
            ))
            .await?;
        sender.wait_for_receiver().await?;
        sender.send(bytes).await?;
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("Worker 启动公告发送超时")
    .and_then(|result| result);
    match result {
        Ok(()) => println!(
            "Worker 启动公告已发布: 实例={}; 未确认 Authority 收录",
            announcement.worker_instance_id
        ),
        Err(error) => eprintln!(
            "Worker 启动公告未确认: 实例={}; {error}; 不自动重试, 不影响接收 Attempt",
            announcement.worker_instance_id
        ),
    }
}
