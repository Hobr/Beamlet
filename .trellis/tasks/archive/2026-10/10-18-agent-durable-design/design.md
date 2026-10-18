# 文档修订设计

## 已确认的目标

用户已在本次会话确认模型并要求创建任务更新设计，代码实现另建任务。正文归属、事务和恢复的完整设计落在 [主设计](../../../../../docs/architecture/agent-operation-persistence.md)，本文件仅记录文档组织，避免两份设计漂移。

## 文档组织

- 主设计完整替换旧检查点主导模型，保留权威/执行证据、停止 provenance、存储运维和不确定性边界。
- persistence-delivery.md 替换成新模型的后续实施/验收计划，旧 Stage A–F 证据仅作历史，不算新方案验收。
- GLOSSARY.md 对齐领域定义，双语 architecture 入口指向修订并标明基线性质。
- backend spec 只增加目标与当前实现区别，保留现有签名/行为，避免文档伪造新 API。
- research 文档保留旧研究，并显式说明旧决策已被替代；DeepSeek-Harness 总结无一手源码核验。

## 边界与取舍

Agent 保存原始输入/配置与编排引用；Operation 固定请求和来源；accepted Result 固定业务输出；executor journal 保留证据。消除 Agent 正文副本，不承诺跨节点物理零重复。fork 继承直接不可变内容引用，生命周期独立而非删除依赖独立。连续 Agent 提交序号不能复用旧 accept_seq 预留方式。

## 兼容与回退

未来实现不要求旧格式兼容。本任务无数据操作；设计文档可以通过普通版本控制回退，但不得把回退文档理解成数据库降级许可。所有新 reducer/API/schema 仍需独立实现任务评审。
