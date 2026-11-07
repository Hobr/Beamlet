//! 有界原授权交付, 回执与 Report 均可终止重投, 不重新授权
use anyhow::{Result, ensure};
use beamlet_agent::{
    Limits,
    id::OperationId,
    model::Delivery,
    testing::{
        attempt_receipt::AttemptAccepted,
        hello::{Dispatch, Task},
        protocol::Limits as ProtocolLimits,
    },
};
use std::collections::HashMap;
use tokio::time::{Duration, Instant};

struct Entry {
    expected: AttemptAccepted,
    bytes: Option<Vec<u8>>,
    sends: u8,
    in_flight: bool,
    next: Instant,
    deadline: Instant,
    confirmed: bool,
}
pub(crate) struct AttemptDeliveries {
    entries: HashMap<OperationId, Entry>,
    limits: Limits,
}
impl AttemptDeliveries {
    pub(crate) fn new(limits: Limits) -> Self {
        Self {
            entries: HashMap::new(),
            limits,
        }
    }
    pub(crate) fn has_capacity(&self) -> bool {
        self.entries.len() < self.limits.max_records
            && self.entries.values().filter(|v| v.bytes.is_some()).count()
                < self.limits.queue_capacity
    }
    pub(crate) fn retain(
        &mut self,
        dispatch: &Delivery<Task, String, String>,
        protocol: &ProtocolLimits,
    ) -> Result<()> {
        let expected = AttemptAccepted::for_dispatch(dispatch)?;
        let id = OperationId::from_u128(expected.operation_id.as_u128());
        if let Some(old) = self.entries.get(&id) {
            ensure!(old.expected == expected, "Attempt 交付绑定冲突");
            return Ok(());
        }
        ensure!(self.has_capacity(), "Attempt 交付槽位已满");
        self.entries.insert(
            id,
            Entry {
                expected,
                bytes: Some(Dispatch::from_delivery(dispatch)?.to_json(protocol)?),
                sends: 0,
                in_flight: false,
                next: Instant::now(),
                deadline: Instant::now() + Duration::from_secs(5),
                confirmed: false,
            },
        );
        Ok(())
    }
    pub(crate) fn acknowledge(&mut self, receipt: &AttemptAccepted) -> Result<bool> {
        let id = OperationId::from_u128(receipt.operation_id.as_u128());
        let entry = self
            .entries
            .get_mut(&id)
            .ok_or_else(|| anyhow::anyhow!("未知 Attempt 回执"))?;
        ensure!(&entry.expected == receipt, "Attempt 回执完整身份绑定不符");
        let changed = !entry.confirmed;
        entry.confirmed = true;
        entry.bytes = None;
        Ok(changed)
    }
    pub(crate) fn reported(&mut self, id: OperationId) {
        if let Some(entry) = self.entries.get_mut(&id) {
            entry.confirmed = true;
            entry.bytes = None;
        }
    }
    pub(crate) fn sent(&mut self, id: OperationId) {
        if let Some(entry) = self.entries.get_mut(&id) {
            entry.in_flight = false;
            entry.next = Instant::now() + Duration::from_secs(1);
        }
    }
    pub(crate) fn next_send(&mut self) -> Option<(OperationId, String, Vec<u8>)> {
        let now = Instant::now();
        for (id, e) in &mut self.entries {
            if e.bytes.is_none() {
                continue;
            }
            if now >= e.deadline || (!e.in_flight && now >= e.next && e.sends >= 3) {
                e.bytes = None;
                eprintln!("Attempt 交付预算耗尽: Operation={id}; 接纳未确认, 不改派或重新授权");
                continue;
            }
            if !e.in_flight && now >= e.next {
                e.in_flight = true;
                e.sends += 1;
                println!(
                    "Authority 重用原授权发送: Operation={id} Attempt={}; 发送尝试次数={}/3",
                    e.expected.attempt_id, e.sends
                );
                let target = format!(
                    "beamlet/v0/worker/{}/inbox",
                    e.expected.source_instance_id.simple()
                );
                return Some((*id, target, e.bytes.as_ref()?.clone()));
            }
        }
        None
    }
}
