//! 当前入口运行 Agent 提供的单进程假任务演示, 不提供网络服务

#[tokio::main]
async fn main() -> Result<(), beamlet_agent::testing::demo::DemoError> {
    beamlet_agent::testing::demo::print().await
}
