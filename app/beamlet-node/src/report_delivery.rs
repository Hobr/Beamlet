//! 有界易失性 Report 交付记录, 不创建授权, 不重新执行任务

use std::collections::HashMap;

use anyhow::{Result, ensure};
use beamlet_agent::{
    Limits,
    id::ReportId,
    model::Delivery,
    testing::{
        hello::{self, Task},
        protocol::Limits as ProtocolLimits,
        receipt::ReportRetained,
    },
};
use tokio::time::{Duration, Instant};

pub(crate) const SEND_BUDGET: Duration = Duration::from_millis(500);
const ACK_WAIT: Duration = Duration::from_secs(1);
const OBSERVATION_BUDGET: Duration = Duration::from_secs(5);
const MAX_SENDS: u8 = 3;

#[derive(Clone, Copy)]
enum Phase {
    Ready,
    Sending,
    Waiting(Instant),
    Confirmed,
    Exhausted,
}

struct Retained {
    expected: ReportRetained,
    bytes: Option<Vec<u8>>,
    phase: Phase,
    sends: u8,
    deadline: Instant,
}

pub(crate) struct ReportDeliveries {
    records: HashMap<ReportId, Retained>,
    max_records: usize,
    capacity: usize,
}

impl ReportDeliveries {
    pub(crate) fn new(limits: Limits) -> Self {
        Self {
            records: HashMap::new(),
            max_records: limits.max_records,
            capacity: limits.queue_capacity,
        }
    }

    /// 排队执行也预占交付槽位, 避免完成后无法保留待确认事实
    pub(crate) fn has_capacity(&self, pending_execution: usize) -> bool {
        let active = self
            .records
            .values()
            .filter(|record| {
                matches!(
                    record.phase,
                    Phase::Ready | Phase::Sending | Phase::Waiting(_)
                )
            })
            .count();
        active.saturating_add(pending_execution) < self.capacity
    }

    pub(crate) fn retain(
        &mut self,
        report: &Delivery<Task, String, String>,
        protocol: &ProtocolLimits,
    ) -> Result<()> {
        let expected = ReportRetained::for_report(report)?;
        let id = ReportId::from_u128(expected.report_id.as_u128());
        if let Some(record) = self.records.get(&id) {
            ensure!(record.expected == expected, "Report 交付记录绑定冲突");
            return Ok(());
        }
        ensure!(self.records.len() < self.max_records, "Report 交付记录已满");
        ensure!(self.has_capacity(0), "Report 活动交付槽位已满");
        self.records.insert(
            id,
            Retained {
                expected,
                bytes: Some(hello::encode_report(report, protocol)?),
                phase: Phase::Ready,
                sends: 0,
                deadline: Instant::now() + OBSERVATION_BUDGET,
            },
        );
        Ok(())
    }

    /// 未知或错绑定回执不改变状态, 耗尽后仍可确认迟到回执
    pub(crate) fn acknowledge(&mut self, receipt: &ReportRetained) -> Result<bool> {
        let id = ReportId::from_u128(receipt.report_id.as_u128());
        let Some(record) = self.records.get_mut(&id) else {
            anyhow::bail!("未知 Report 收录回执");
        };
        ensure!(
            &record.expected == receipt,
            "Report 收录回执的完整身份绑定不符"
        );
        let changed = !matches!(record.phase, Phase::Confirmed);
        record.phase = Phase::Confirmed;
        record.bytes = None;
        Ok(changed)
    }

    pub(crate) fn sent(&mut self, id: ReportId) {
        if let Some(record) = self.records.get_mut(&id)
            && matches!(record.phase, Phase::Sending)
        {
            record.phase = Phase::Waiting(Instant::now() + ACK_WAIT);
        }
    }

    /// 不在 tick 中补发错过的周期, 不让重复消息重置观察期限
    pub(crate) fn refresh(&mut self) {
        let now = Instant::now();
        for (id, record) in &mut self.records {
            let due = matches!(record.phase, Phase::Waiting(until) if now >= until);
            if matches!(record.phase, Phase::Confirmed | Phase::Exhausted) {
                continue;
            }
            if now >= record.deadline || (due && record.sends >= MAX_SENDS) {
                record.phase = Phase::Exhausted;
                record.bytes = None;
                eprintln!(
                    "Report 交付预算耗尽: Report={id}; 发送尝试次数={}; 收录未确认, 保留原证据, 不重跑",
                    record.sends
                );
            } else if due {
                record.phase = Phase::Ready;
            }
        }
    }

    pub(crate) fn next_send(&mut self) -> Option<(ReportId, Vec<u8>)> {
        let (id, record) = self
            .records
            .iter_mut()
            .find(|(_, record)| matches!(record.phase, Phase::Ready))?;
        let bytes = record.bytes.as_ref()?.clone();
        record.sends += 1;
        record.phase = Phase::Sending;
        println!(
            "Worker 发送原 Report: Report={id}; 发送尝试次数={}/{}; 尚未确认 Authority 收录",
            record.sends, MAX_SENDS
        );
        Some((*id, bytes))
    }

    pub(crate) fn unconfirmed(&self) -> usize {
        self.records
            .values()
            .filter(|record| !matches!(record.phase, Phase::Confirmed))
            .count()
    }
}
