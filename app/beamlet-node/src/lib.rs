//! 固定 Hello 应用角色入口与原型集成测试的兼容导出
//!
//! 应用角色复用 beamlet-agent 驱动; 其余模块只保留旧测试导入路径
pub mod executor;
mod lifecycle;
pub mod memory;
pub mod node;
pub mod protocol;
mod report_delivery;
pub mod roles;
mod shutdown;
