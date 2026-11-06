//! 当前入口运行 Agent 提供的单进程假任务演示, 不提供网络服务

#[tokio::main]
async fn main() -> std::process::ExitCode {
    match beamlet_agent::testing::demo::print().await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("错误: {error:#}");
            std::process::ExitCode::FAILURE
        }
    }
}
