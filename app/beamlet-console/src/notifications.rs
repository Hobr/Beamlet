//! Client 可选的只读启动通知订阅, 不发布 Client 生命周期消息

use std::collections::HashMap;

use anyhow::{Context, Result, ensure};
use beamlet_agent::testing::lifecycle::RoleStarted;
use beamlet_message_zenoh::Transport;
use uuid::Uuid;

const MAX_INSTANCES: usize = 256;

pub(crate) async fn receive(transport: Transport) -> Result<()> {
    let mut retained: HashMap<Uuid, RoleStarted> = HashMap::new();
    loop {
        let message = match transport.recv_message().await {
            Ok(message) => message,
            Err(
                error @ (beamlet_message_zenoh::Error::UnexpectedDelete
                | beamlet_message_zenoh::Error::MessageTooLarge),
            ) => {
                eprintln!("已忽略角色启动通知: {error}");
                continue;
            }
            Err(error) => return Err(error).context("接收角色启动通知失败"),
        };
        let result = (|| {
            let notice = RoleStarted::from_json(&message.payload)?;
            ensure!(
                message.key_expr == notice.topic(),
                "角色启动通知路由与身份不符"
            );
            if let Some(previous) = retained.get(&notice.role_instance_id) {
                ensure!(previous == &notice, "角色启动通知与已保留实例归属冲突");
                return Ok(());
            }
            ensure!(
                retained.len() < MAX_INSTANCES,
                "Client 启动通知记录已满, 不淘汰已有实例"
            );
            println!(
                "Client 收到 {} 启动公告: 逻辑身份={} 运行实例={} NodeId={} NodeInstanceId={}; 可为重播, 不代表当前在线",
                notice.role,
                notice.role_id,
                notice.role_instance_id,
                notice.node_id,
                notice.node_instance_id
            );
            retained.insert(notice.role_instance_id, notice);
            Ok::<_, anyhow::Error>(())
        })();
        if let Err(error) = result {
            eprintln!("已忽略角色启动通知: {error}");
        }
    }
}
