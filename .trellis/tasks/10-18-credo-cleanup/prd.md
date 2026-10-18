# 合并后 Credo 清零（durable/storage）

## Goal and Source

`feat/durable-storage` 合并进 `dev` 后，`mix credo`（默认）退出 12、`mix credo --strict` 退出 14。
全部 106 项集中在 durable/storage 新增代码（`apps/beamlet_agent`、
`apps/beamlet_runtime`、`apps/beamlet_storage`，以及它们的测试）。本任务只做
**行为等价的重构**，让两条 Credo 命令都退出 0，从而恢复项目既有的质量门。

## Requirements

- C1：`mix credo` 退出 0，`mix credo --strict` 退出 0（无新增 `.credo.exs`、无
  `--ignore`、无目录排除、无规则降级）。
- C2：不改变任何业务/协议/持久化语义：不修改 schema、迁移、事务边界、CAS、
  admission、恢复/继续/fork/export 的判定与返回值；不弱化或删除既有断言；
  不加超时、重试或容错来掩盖问题。
- C3：测试文件同样清零；测试覆盖的路径与断言强度保持等价，不得为通过而移除
  用例或减少断言。
- C4：保持公开 API 与模块名不变；仅允许新增私有辅助函数、私有模块或顶层
  `alias`。
- C5：不修改 `mix.lock`、依赖版本、发布配置或部署脚本；不改动 Web/i18n 行为。
- C6：修复方式优先使用 Credo 提示的安全模式：`alias` 取代长模块名、抽取私有
  辅助函数降低嵌套/复杂度、`case`/`if` 取代单分支 `with` 或 `cond`、`unless`
  消除多余 `else`、拆分长 `quote`。

## Acceptance Criteria

- [ ] CA1：`mix credo` 与 `mix credo --strict` 均退出 0，且 `mix credo --strict --all`
      输出无 issue。
- [ ] CA2：`mix format --check-formatted`、`mix compile --warnings-as-errors` 通过。
- [ ] CA3：伞项目普通测试全绿且通过数不少于合并后基线（439 通过 / 49 排除）；
      storage 套件 59 通过 / 13 排除（`:postgres_db` 与 durable e2e 阶段仍按设计排除）。
- [ ] CA4：命名 VM 分布式测试 33 通过（runtime 6、node 20、daemon 2、web 5）。
- [ ] CA5：`scripts/deployment/durable-e2e.sh` 两阶段通过；`mix dialyzer` 0 错误；
      `mix sobelow`、`mix gettext.extract --check-up-to-date` 通过。
- [ ] CA6：`git diff` 中无 schema/迁移/公开函数签名变化；无 `mix.lock` 变化。

## Out of Scope

- 新的功能、协议或持久化原语；性能优化。
- 为 Credo 之外的静态检查（如新增 Dialyzer 注解）做额外改造。
- Web/i18n/CLI 的既有债务（它们的 Credo 状态已干净）。
- 把 durable 代码拆成新应用或重命名模块。

## Dependencies

前置：`9c6354d`（合并）与 `dfa90cb`（文档对齐）。合并时已确认：
普通测试 439/49、storage 59/13、分布式 33、durable e2e、release 检查、
Dialyzer 0 均通过；唯一红灯是 Credo。
