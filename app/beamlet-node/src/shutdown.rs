//! 应用层统一退出信号与有限 Draining, 不推断执行或外部效果

use std::future::Future;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use tokio::{sync::watch, time::timeout};

pub(crate) const DEFAULT_DRAIN_MS: u64 = 10_000;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Phase {
    Running,
    Draining,
}

#[derive(Clone, Debug)]
pub(crate) struct Shutdown {
    receiver: watch::Receiver<Phase>,
}

impl Shutdown {
    pub(crate) fn channel() -> (watch::Sender<Phase>, Self) {
        let (sender, receiver) = watch::channel(Phase::Running);
        (sender, Self { receiver })
    }

    pub(crate) fn is_draining(&self) -> bool {
        *self.receiver.borrow() == Phase::Draining || self.receiver.has_changed().is_err()
    }

    pub(crate) async fn requested(&mut self) {
        let _ = self
            .receiver
            .wait_for(|phase| *phase == Phase::Draining)
            .await;
    }
}

pub(crate) async fn standalone<F, Fut>(start: F) -> Result<()>
where
    F: FnOnce(Shutdown) -> Fut,
    Fut: Future<Output = Result<()>>,
{
    let (sender, control) = Shutdown::channel();
    let driver = start(control);
    tokio::pin!(driver);
    tokio::select! {
        result = &mut driver => return result,
        signal = tokio::signal::ctrl_c() => { signal.context("接收退出信号失败")?; }
    }
    sender.send_replace(Phase::Draining);
    println!(
        "Node 进入 Draining: 停止新接纳; 等待上限={} 毫秒",
        DEFAULT_DRAIN_MS
    );
    match timeout(Duration::from_millis(DEFAULT_DRAIN_MS), &mut driver).await {
        Ok(result) => result,
        Err(_) => {
            bail!("Node Draining 到期; 执行或交付未确认, 不生成失败 Report, 内存状态不保证恢复")
        }
    }
}
