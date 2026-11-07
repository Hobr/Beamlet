//! Node 组合入口, 网络会话与静态业务角色分别配置

use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

use anyhow::{Context, Result, ensure};
use beamlet_agent::{
    Worker,
    id::{
        AuthorityId, AuthorityInstanceId, NodeId, NodeInstanceId, RoleInstanceId, WorkerId,
        WorkerInstanceId,
    },
    testing::{
        hello::Task,
        lifecycle::{ExitOutcome, Role, RoleNotice},
    },
};
use beamlet_message_zenoh::{Limits, Transport};
use serde::Deserialize;
use tokio::{
    fs,
    task::JoinSet,
    time::{Duration, timeout},
};
use uuid::Uuid;

use crate::{
    lifecycle::{self, Announcement, Observations},
    roles,
    shutdown::{self, Phase, Shutdown},
};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    node_id: Uuid,
    #[serde(default = "default_drain_ms")]
    drain_timeout_ms: u64,
    #[serde(default)]
    listen: Vec<String>,
    #[serde(default)]
    connect: Vec<String>,
    #[serde(default)]
    authorities: Vec<AuthorityConfig>,
    #[serde(default)]
    workers: Vec<WorkerConfig>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct AuthorityConfig {
    id: Uuid,
    instance: Uuid,
    workers: Vec<Uuid>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct WorkerConfig {
    id: Uuid,
    instance: Uuid,
    authority: Uuid,
}

fn default_drain_ms() -> u64 {
    shutdown::DEFAULT_DRAIN_MS
}

impl Config {
    fn validate(&self) -> Result<()> {
        ensure!(
            (1..=60_000).contains(&self.drain_timeout_ms),
            "Draining 期限必须为 1..=60000 毫秒"
        );
        ensure!(
            !self.listen.is_empty() || !self.connect.is_empty(),
            "至少配置一个监听或连接地址"
        );
        ensure!(
            self.authorities.len() + self.workers.len() <= 64,
            "每个 Node 最多配置 64 个角色实例"
        );
        let mut identities = HashSet::new();
        for identity in self
            .authorities
            .iter()
            .map(|a| a.id)
            .chain(self.workers.iter().map(|w| w.id))
        {
            ensure!(identities.insert(identity), "逻辑角色身份重复: {identity}");
        }
        let mut instances = HashSet::new();
        for instance in self
            .authorities
            .iter()
            .map(|a| a.instance)
            .chain(self.workers.iter().map(|w| w.instance))
        {
            ensure!(instances.insert(instance), "角色实例身份重复: {instance}");
        }
        for authority in &self.authorities {
            let mut workers = HashSet::new();
            ensure!(
                authority.workers.len() <= lifecycle::MAX_WORKERS,
                "每个 Authority 最多配置 64 个 Worker 实例"
            );
            ensure!(
                !authority.workers.is_empty(),
                "Authority 至少需要一个 Worker"
            );
            for worker in &authority.workers {
                ensure!(
                    *worker != authority.instance && workers.insert(*worker),
                    "Worker 绑定无效或重复"
                );
                ensure!(
                    !self.authorities.iter().any(|a| a.instance == *worker),
                    "Worker 目标指向了 Authority 实例"
                );
                if let Some(local) = self.workers.iter().find(|w| w.instance == *worker) {
                    ensure!(
                        local.authority == authority.instance,
                        "本地 Worker 绑定了其他 Authority"
                    );
                }
            }
        }
        for worker in &self.workers {
            ensure!(worker.instance != worker.authority, "Worker 不能授权自身");
            if let Some(local) = self
                .authorities
                .iter()
                .find(|a| a.instance == worker.authority)
            {
                ensure!(
                    local.workers.contains(&worker.instance),
                    "本地 Authority 未配置此 Worker"
                );
            }
        }
        Ok(())
    }
}

/// 从有界 JSON 配置启动共享消息会话及角色, 零角色可作为消息连接节点
///
/// # 错误
/// 配置超限, 字段或角色绑定无效, 会话或角色驱动失败时返回错误
pub async fn run(path: &str) -> Result<()> {
    use tokio::io::AsyncReadExt;

    let file = fs::File::open(path).await.context("打开 Node 配置失败")?;
    let mut bytes = Vec::new();
    file.take(64 * 1024 + 1).read_to_end(&mut bytes).await?;
    ensure!(bytes.len() <= 64 * 1024, "Node 配置超过 64 KiB");
    let config: Config = serde_json::from_slice(&bytes).context("解析 Node 配置失败")?;
    config.validate()?;
    let node_id = NodeId::from_u128(config.node_id.as_u128());
    let node_instance = NodeInstanceId::from_u128(Uuid::new_v4().as_u128());
    println!("Node 身份: 逻辑身份={node_id} 运行实例={node_instance}");
    let mut notices = Vec::new();
    for authority in &config.authorities {
        notices.push(RoleNotice::new(
            Role::Authority,
            config.node_id,
            Uuid::from_u128(node_instance.as_u128()),
            authority.id,
            authority.instance,
        ));
        let id = AuthorityId::from_u128(authority.id.as_u128());
        let instance = AuthorityInstanceId::from_u128(authority.instance.as_u128());
        println!(
            "Authority 身份: 逻辑身份={id} 运行实例={instance} 所属 Node 实例={node_instance}"
        );
    }
    for worker in &config.workers {
        notices.push(RoleNotice::new(
            Role::Worker,
            config.node_id,
            Uuid::from_u128(node_instance.as_u128()),
            worker.id,
            worker.instance,
        ));
        let id = WorkerId::from_u128(worker.id.as_u128());
        let instance = WorkerInstanceId::from_u128(worker.instance.as_u128());
        println!("Worker 身份: 逻辑身份={id} 运行实例={instance} 所属 Node 实例={node_instance}");
    }
    let subscription = format!("beamlet/v0/node-session/{node_instance}/inbox");
    let transport = Arc::new(
        Transport::node(
            &config.listen,
            &config.connect,
            &subscription,
            Limits::default(),
        )
        .await?,
    );
    let mut tasks = JoinSet::new();
    let (stop, control) = Shutdown::channel();
    let mut announcements_task = JoinSet::new();
    // 先声明所有订阅再启动角色, 避免共享会话中的局部启动顺序影响就绪
    let mut authorities = Vec::new();
    let mut workers = Vec::new();
    for authority in config.authorities {
        let prefix = format!(
            "beamlet/v0/authority/{}/submit/",
            authority.instance.simple()
        );
        let requests = transport.subscribe(&format!("{prefix}*")).await?;
        let instance: RoleInstanceId =
            AuthorityInstanceId::from_u128(authority.instance.as_u128()).into();
        let reports = transport.subscribe(&roles::report_inbox(instance)).await?;
        // 两种地址各有独立有界队列, 由同一 Authority 驱动处理
        let combined = (requests, reports);
        let announcements = transport
            .subscribe(&lifecycle::inbox(authority.instance))
            .await?;
        let mut observations = Observations::new(authority.instance, &authority.workers)?;
        let mut local = HashMap::new();
        let mut local_announcements = Vec::new();
        for worker in config
            .workers
            .iter()
            .filter(|w| w.authority == authority.instance)
        {
            let worker_id: RoleInstanceId =
                WorkerInstanceId::from_u128(worker.instance.as_u128()).into();
            local.insert(
                worker_id,
                Worker::<Task, String, String>::new(
                    instance,
                    vec![worker_id],
                    beamlet_agent::Limits::default(),
                )?,
            );
            let announcement = Announcement::started(
                config.node_id,
                Uuid::from_u128(node_instance.as_u128()),
                worker.id,
                worker.instance,
                worker.authority,
            );
            observations.record(announcement.clone())?;
            local_announcements.push(announcement);
        }
        authorities.push((
            combined,
            authority,
            local,
            prefix,
            (observations, announcements, local_announcements),
        ));
    }
    for worker in config.workers {
        if authorities
            .iter()
            .any(|(_, a, _, _, _)| a.instance == worker.authority)
        {
            continue;
        }
        let inbox = roles::worker_inbox(worker.instance.as_u128().into());
        workers.push((transport.subscribe(&inbox).await?, worker));
    }
    for (
        (requests, reports),
        authority,
        local,
        prefix,
        (observations, announcements, local_announcements),
    ) in authorities
    {
        let control = control.clone();
        let mut instances: Vec<Uuid> = local
            .keys()
            .map(|id| Uuid::from_u128(id.as_u128()))
            .collect();
        instances.push(authority.instance);
        tasks.spawn(async move {
            let result = tokio::select! {
                result = roles::serve_authority_pair(
                    Arc::new(requests),
                    Some(reports),
                    roles::AuthoritySetup {
                        instance: authority.instance.as_u128().into(),
                        workers: authority.workers.into_iter().map(|id| id.as_u128().into()).collect(),
                        local_workers: local,
                        request_prefix: prefix,
                    },
                    control,
                ) => result,
                result = observations.serve(announcements, local_announcements) => result,
            };
            (instances, result)
        });
    }
    for (worker_transport, worker) in workers {
        let announcement = Announcement::started(
            config.node_id,
            Uuid::from_u128(node_instance.as_u128()),
            worker.id,
            worker.instance,
            worker.authority,
        );
        let publisher = Arc::clone(&transport);
        let control = control.clone();
        tasks.spawn(async move {
            let result = tokio::select! {
                result = lifecycle::maintain(&publisher, announcement) => result,
                result = roles::serve_worker(
                    worker_transport,
                    worker.instance.as_u128().into(),
                    worker.authority.as_u128().into(),
                    control,
                ) => result,
            };
            (vec![worker.instance], result)
        });
    }
    let role_count = tasks.len();
    let mut outcomes: HashMap<Uuid, ExitOutcome> = notices
        .iter()
        .map(|notice| (notice.role_instance_id, ExitOutcome::Unconfirmed))
        .collect();
    if !notices.is_empty() {
        let publisher = Arc::clone(&transport);
        let starts = notices.clone();
        announcements_task
            .spawn(async move { lifecycle::publish_starts(&publisher, starts).await });
    }
    println!("Node 已就绪: 消息会话共享; 角色数量={role_count}");
    let failure = tokio::select! {
        finished = tasks.join_next(), if !tasks.is_empty() => {
            Some(finished.context("角色完成记录缺失")
                .and_then(|result| result.context("角色任务失败"))
                .and_then(|(_, result)| result)
                .err().unwrap_or_else(|| anyhow::anyhow!("角色意外停止")))
        }
        finished = announcements_task.join_next(), if !announcements_task.is_empty() => {
            Some(finished.context("公告完成记录缺失")
                .and_then(|result| result.context("公告任务失败"))
                .and_then(|result| result)
                .err().unwrap_or_else(|| anyhow::anyhow!("公告任务意外停止")))
        }
        signal = tokio::signal::ctrl_c() => {
            signal.context("接收退出信号失败").err()
        }
    };
    stop.send_replace(Phase::Draining);
    println!(
        "Node 进入 Draining: 停止新接纳; 等待上限={} 毫秒",
        config.drain_timeout_ms
    );
    // 停止对外重播, 共享会话保留到角色退出和发送尝试结束之后
    announcements_task.abort_all();
    while announcements_task.join_next().await.is_some() {}
    let mut failure = failure;
    let drained = timeout(Duration::from_millis(config.drain_timeout_ms), async {
        while let Some(result) = tasks.join_next().await {
            let result = result
                .context("Draining 角色任务失败")
                .and_then(|(instances, result)| {
                    if result.is_ok() {
                        for instance in instances {
                            outcomes.insert(instance, ExitOutcome::Drained);
                        }
                    }
                    result
                });
            if let Err(error) = result {
                eprintln!("Draining 角色未正常完成: {error}; 不生成失败 Report");
                if failure.is_none() {
                    failure = Some(error);
                }
            }
        }
    })
    .await;
    if drained.is_err() {
        eprintln!(
            "Node Draining 到期: 剩余角色={}; 执行或交付未确认, 不生成失败 Report; 中止后内存状态不保证恢复",
            tasks.len()
        );
        tasks.abort_all();
        while tasks.join_next().await.is_some() {}
        failure = Some(anyhow::anyhow!("Node Draining 到期, 未确认执行或交付"));
    }
    lifecycle::publish_exits(&transport, notices, &outcomes).await;
    if let Some(error) = failure {
        return Err(error);
    }
    println!("Node Draining 完成: 角色已停止, 随后关闭消息会话; 不提供跨重启恢复");
    Ok(())
}
