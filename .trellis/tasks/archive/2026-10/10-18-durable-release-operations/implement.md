# 持久化发布与运维验收执行计划

状态：in_progress。用户于 2026-10-18 授权 A–F 连续实施；先决 A–E 已验收并提交（3aefa85、11577fb、f7be001、22d6159、c4b37fd）。

## 开工门

- [x] 用户批准连续实施；先决：[持久数据契约与存储基础](../10-18-durable-storage/prd.md)、[Runtime 权威记录与执行日志](../10-18-durable-runtime/prd.md)、[Agent 历史、检查点与暂停恢复](../10-18-durable-agent/prd.md)、[持久历史查询与轨迹导出](../10-18-durable-history-export/prd.md)、[安全 fork 与恢复决定](../10-18-durable-fork-resolution/prd.md) 验收通过后才能实施。
- [x] 重新核对主设计、父设计和当前代码；记录本阶段具体接口、默认资源上限及验收命令。
- [x] 验证上下文 manifests，随后才可激活本子任务。父子链接本身不满足依赖或授权门。

## 实施顺序

- [x] 确认 A–E 阶段证据齐备，核对当前宿主/release/CI 结构并锁定配置和运维命令。
- [x] 接入角色所需 Repo、持久准入状态、安全错误与运维文档，保持临时入口显式可选。
- [x] 构建双库 CI 和本地持久卷 release 场景，覆盖所有角色及注册未丢失的存储故障。
- [x] 隔离验证备份恢复与 journal 丢失流程，完成父任务端到端验收，记录未覆盖的故障模型及发布/回退限制。

## 验证与收尾

- [x] 逐项取得自身 PRD 验收及[主交付计划](../../../../../docs/architecture/persistence-delivery.md)阶段 F 的真实证据；纯存储阶段不声称已验证业务恢复。
- [x] 按 backend/quality-guidelines 选择受影响代码的格式、warning-fatal compile、针对性/完整 ExUnit、显式 named distributed suite、静态检查和必要 release 验证，记录环境限制；涉及两库契约的用例必须两库运行。
- [x] 更新已实现的 spec、接口和操作说明，不把下游规划写成现状；将证据及交接契约交给父任务和下游评审。
- [x] 依父设计暂停点检查范围，阶段回退只关闭新持久入口/保持兼容读，不删除已提交事实或回退成内存权威。
