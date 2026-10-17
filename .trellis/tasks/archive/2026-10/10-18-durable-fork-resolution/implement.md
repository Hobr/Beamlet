# 安全 fork 与恢复决定执行计划

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施；先决 A–D 已验收并提交（3aefa85、11577fb、f7be001、22d6159）。

## 开工门

- [x] 用户批准连续实施；先决：[Agent 历史、检查点与暂停恢复](../10-18-durable-agent/prd.md)、[持久历史查询与轨迹导出](../10-18-durable-history-export/prd.md) 验收通过后才能实施。
- [x] 重新核对主设计、父设计和当前代码；记录本阶段具体接口、默认资源上限及验收命令。
- [x] 验证上下文 manifests，随后才可激活本子任务。父子链接本身不满足依赖或授权门。

## 实施顺序

- [x] 确认 C、D 均已验收，收敛 safe_to_fork、复制大小上限、环境风险及 resolution 数据契约。
- [x] 实现源冻结/本地发送者退役、安全核查、同事务 fork 复制及幂等新 locator。
- [x] 实现显式采纳/放弃/风险接受和新 Operation 关联；迟到证据仅影响原对象。
- [x] 注入复制切点故障，验证独立加载、外部效果不撤销、真实 fork 的历史与导出；更新接口说明。

## 验证与收尾

- [x] 逐项取得自身 PRD 验收及[主交付计划](../../../docs/architecture/persistence-delivery.md)阶段 E 的真实证据；纯存储阶段不声称已验证业务恢复。
- [x] 按 backend/quality-guidelines 选择受影响代码的格式、warning-fatal compile、针对性/完整 ExUnit、显式 named distributed suite、静态检查和必要 release 验证，记录环境限制；涉及两库契约的用例必须两库运行。
- [x] 更新已实现的 spec、接口和操作说明，不把下游规划写成现状；将证据及交接契约交给父任务和下游评审。
- [x] 依父设计暂停点检查范围，阶段回退只关闭新持久入口/保持兼容读，不删除已提交事实或回退成内存权威。
