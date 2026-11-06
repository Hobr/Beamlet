//! 配置模式的 Worker 生命周期观察, 不授予执行权或调度资格

use std::{collections::HashMap, time::Duration};

use anyhow::{Context, Result, ensure};
use beamlet_message_zenoh::Transport;
use serde::{Deserialize, Serialize};
use tokio::time::{Instant, MissedTickBehavior, interval, timeout};
use uuid::Uuid;

pub(crate) const MAX_WORKERS: usize = 64;
const MAX_ANNOUNCEMENT_BYTES: usize = 4096;
const ANNOUNCE_TIMEOUT: Duration = Duration::from_secs(10);
const HEARTBEAT_PERIOD: Duration = Duration::from_secs(1);
const HEARTBEAT_SEND_TIMEOUT: Duration = Duration::from_millis(500);
const SUSPECT_AFTER: Duration = Duration::from_secs(4);
const OBSERVATION_PERIOD: Duration = Duration::from_millis(250);

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum Kind {
    WorkerStarted,
    WorkerHeartbeat,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    sequence: Option<u64>,
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
            sequence: None,
        }
    }

    fn heartbeat(&self, sequence: u64) -> Self {
        Self {
            kind: Kind::WorkerHeartbeat,
            sequence: Some(sequence),
            ..self.clone()
        }
    }

    fn same_binding(&self, other: &Self) -> bool {
        self.node_id == other.node_id
            && self.node_instance_id == other.node_instance_id
            && self.worker_id == other.worker_id
            && self.worker_instance_id == other.worker_instance_id
            && self.authority_instance_id == other.authority_instance_id
    }

    fn validate(&self) -> Result<()> {
        ensure!(self.protocol_version == 0, "Worker 生命周期消息版本不支持");
        ensure!(
            match self.kind {
                Kind::WorkerStarted => self.sequence.is_none(),
                Kind::WorkerHeartbeat => self.sequence.is_some_and(|sequence| sequence > 0),
            },
            "Worker 心跳序号无效或启动公告携带了序号"
        );
        Ok(())
    }

    fn from_json(bytes: &[u8]) -> Result<Self> {
        ensure!(
            bytes.len() <= MAX_ANNOUNCEMENT_BYTES,
            "Worker 生命周期消息超过字节上限"
        );
        let announcement: Self =
            serde_json::from_slice(bytes).context("Worker 生命周期消息格式无效")?;
        announcement.validate()?;
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Status {
    Unobserved,
    Online,
    Suspected,
}

#[derive(Debug)]
struct HeartbeatObservation {
    sequence: u64,
    received_at: Instant,
}

#[derive(Debug)]
struct Observation {
    binding: Option<Announcement>,
    created_at: Instant,
    heartbeat: Option<HeartbeatObservation>,
    status: Status,
}

#[derive(Debug)]
pub(crate) struct Observations {
    authority: Uuid,
    workers: HashMap<Uuid, Observation>,
}

impl Observations {
    pub(crate) fn new(authority: Uuid, workers: &[Uuid]) -> Result<Self> {
        ensure!(workers.len() <= MAX_WORKERS, "Worker 公告观察数量超过上限");
        let now = Instant::now();
        let entries: HashMap<_, _> = workers
            .iter()
            .map(|worker| {
                (
                    *worker,
                    Observation {
                        binding: None,
                        created_at: now,
                        heartbeat: None,
                        status: Status::Unobserved,
                    },
                )
            })
            .collect();
        ensure!(entries.len() == workers.len(), "Worker 公告观察实例重复");
        Ok(Self {
            authority,
            workers: entries,
        })
    }

    pub(crate) fn record(&mut self, announcement: Announcement) -> Result<()> {
        announcement.validate()?;
        ensure!(
            announcement.authority_instance_id == self.authority,
            "Worker 生命周期消息属于其他 Authority 实例"
        );
        let retained = self
            .workers
            .get_mut(&announcement.worker_instance_id)
            .context("Worker 生命周期消息实例不在配置列表中")?;
        if let Some(previous) = &retained.binding {
            ensure!(
                previous.same_binding(&announcement),
                "Worker 生命周期消息与已保留的实例归属冲突"
            );
        }
        // 先校验序号再更新任何绑定或本地观察时间, 重放不能恢复在线状态
        if let Some(sequence) = announcement.sequence {
            ensure!(
                retained
                    .heartbeat
                    .as_ref()
                    .is_none_or(|previous| sequence > previous.sequence),
                "Worker 心跳重复或倒序, 不刷新观察时间"
            );
            let now = Instant::now();
            let expired = retained
                .heartbeat
                .as_ref()
                .is_some_and(|previous| now.duration_since(previous.received_at) >= SUSPECT_AFTER);
            if expired && retained.status == Status::Online {
                println!(
                    "Authority 心跳观察: 实例={} WorkerInstanceId={} 状态=可疑; 心跳观察已超时, 不代表执行停止",
                    self.authority, announcement.worker_instance_id
                );
            }
            if retained.status != Status::Online || expired {
                println!(
                    "Authority 心跳观察: 实例={} WorkerInstanceId={} 状态=在线; sequence={sequence}; 仅为近期消息观察, 不代表执行接纳",
                    self.authority, announcement.worker_instance_id
                );
            }
            retained.heartbeat = Some(HeartbeatObservation {
                sequence,
                received_at: now,
            });
            retained.status = Status::Online;
        } else if retained.binding.is_some() {
            println!(
                "Authority 重复公告: 实例={} Worker 实例={}; 保留原记录, 不刷新心跳",
                self.authority, announcement.worker_instance_id
            );
        }
        if retained.binding.is_none() {
            let source = match announcement.kind {
                Kind::WorkerStarted => "启动公告",
                Kind::WorkerHeartbeat => "心跳绑定",
            };
            println!(
                "Authority 已记录 Worker {source}: 实例={} WorkerId={} WorkerInstanceId={} NodeId={} NodeInstanceId={}; 绑定不是身份认证或执行接纳",
                self.authority,
                announcement.worker_id,
                announcement.worker_instance_id,
                announcement.node_id,
                announcement.node_instance_id
            );
            retained.binding = Some(announcement);
        }
        Ok(())
    }

    fn expire(&mut self) {
        let now = Instant::now();
        for (worker, retained) in &mut self.workers {
            let last = retained
                .heartbeat
                .as_ref()
                .map_or(retained.created_at, |heartbeat| heartbeat.received_at);
            if now.duration_since(last) >= SUSPECT_AFTER && retained.status != Status::Suspected {
                retained.status = Status::Suspected;
                println!(
                    "Authority 心跳观察: 实例={} WorkerInstanceId={worker} 状态=可疑; 心跳观察已超时或尚未收到, 不代表执行停止",
                    self.authority
                );
            }
        }
    }

    pub(crate) async fn serve(
        mut self,
        transport: Transport,
        local: Vec<Announcement>,
    ) -> Result<()> {
        let mut clock = interval(OBSERVATION_PERIOD);
        clock.set_missed_tick_behavior(MissedTickBehavior::Skip);
        let mut local_clock = interval(HEARTBEAT_PERIOD);
        local_clock.set_missed_tick_behavior(MissedTickBehavior::Skip);
        let mut sequence = 0_u64;
        loop {
            let received = tokio::select! {
                _ = clock.tick() => { self.expire(); continue; }
                _ = local_clock.tick(), if !local.is_empty() => {
                    sequence = sequence.checked_add(1).context("本地 Worker 心跳序号已耗尽")?;
                    for announcement in &local { self.record(announcement.heartbeat(sequence))?; }
                    continue;
                }
                received = transport.recv_message() => received,
            };
            let message = match received {
                Ok(message) => message,
                Err(
                    error @ (beamlet_message_zenoh::Error::MessageTooLarge
                    | beamlet_message_zenoh::Error::UnexpectedDelete),
                ) => {
                    eprintln!("已忽略 Worker 生命周期消息: {error}");
                    continue;
                }
                Err(error) => return Err(error).context("接收 Worker 生命周期消息失败"),
            };
            let result = (|| {
                let announcement = Announcement::from_json(&message.payload)?;
                ensure!(
                    message.key_expr
                        == destination(self.authority, announcement.worker_instance_id),
                    "Worker 生命周期消息路由与实例绑定不符"
                );
                ensure!(
                    !local
                        .iter()
                        .any(|worker| worker.worker_instance_id == announcement.worker_instance_id),
                    "本地 Worker 生命周期消息只接受类型化交付"
                );
                self.record(announcement)
            })();
            if let Err(error) = result {
                eprintln!("已忽略 Worker 生命周期消息: {error}");
            }
        }
    }
}

async fn publish(
    transport: &Transport,
    announcement: &Announcement,
    budget: Duration,
) -> Result<()> {
    timeout(budget, async {
        let bytes = serde_json::to_vec(announcement)?;
        ensure!(
            bytes.len() <= MAX_ANNOUNCEMENT_BYTES,
            "Worker 生命周期消息超过字节上限"
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
    .context("Worker 生命周期消息发送超时")?
}

async fn announce(transport: &Transport, announcement: &Announcement) {
    match publish(transport, announcement, ANNOUNCE_TIMEOUT).await {
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

async fn heartbeats(transport: &Transport, announcement: &Announcement) -> Result<()> {
    let mut clock = interval(HEARTBEAT_PERIOD);
    clock.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let mut sequence = 0_u64;
    let mut publication_failed = false;
    loop {
        clock.tick().await;
        sequence = sequence.checked_add(1).context("Worker 心跳序号已耗尽")?;
        match publish(
            transport,
            &announcement.heartbeat(sequence),
            HEARTBEAT_SEND_TIMEOUT,
        )
        .await
        {
            Ok(()) => {
                if publication_failed {
                    println!(
                        "Worker 心跳发布恢复: 实例={}; 未确认 Authority 收录",
                        announcement.worker_instance_id
                    );
                }
                publication_failed = false;
            }
            Err(error) => {
                if !publication_failed {
                    eprintln!(
                        "Worker 心跳发布未确认: 实例={}; {error}; 丢弃本次观察, 不影响 Attempt 或 Report",
                        announcement.worker_instance_id
                    );
                }
                publication_failed = true;
            }
        }
    }
}

pub(crate) async fn maintain(transport: &Transport, announcement: Announcement) -> Result<()> {
    tokio::try_join!(
        async {
            announce(transport, &announcement).await;
            Ok::<_, anyhow::Error>(())
        },
        heartbeats(transport, &announcement),
    )
    .map(|_| ())
}
