//! 原型集成测试的兼容入口, 不包含领域, 排队或执行实现
//!
//! 应用通过 beamlet-agent 驱动用例; 这些模块只保留旧测试导入路径

pub mod executor;
pub mod memory;
pub mod protocol;
