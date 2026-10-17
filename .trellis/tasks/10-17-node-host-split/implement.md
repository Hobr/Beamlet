# 总体执行与最终集成计划

## Phase gate and order

- [x] 最终摘要呈现后，用户已明确回复“确认”批准实施；从 node-library 子任务开始，不启动仅协调的父任务来写产品代码。
- [x] 子任务顺序：node-library → daemon-host → agent-discovery → cli-host。每一步先读取自身 PRD/design/implement 和 jsonl，再 implement → 独立 check。
- [x] 任何产品范围/接口语义实质变化回到父任务规划；不能把本文件当作已经获得实施授权。

## Integration checklist

- [x] Node：无 Application 自动启动；七种库级组合、共享连接机制、旧终端代码/测试迁移。
- [x] Daemon：同一产物的默认/authority-only/executor-only 选择、配置校验、一次连接结果、独立 release；无 interaction。
- [x] Discovery：本机/远程 list/lookup、可信集群聚合、5秒预算/8并发/32节点/1MiB边界、同名/ID复用及 worker 清理。
- [x] CLI：stdin 会话、命令解析、创建配置、别名、查找附着、EOF/退出不关闭 Agent、独立 release。
- [x] 维护部署示例、copied/named 检查及当前 README/spec；旧 Node 可执行和旧 namespace 搜索清零（历史 archive/journal 不修改）。
- [x] 在父任务逐项验收 AC1..AC9；验证未来 Web 通过 Node 三角色组合测试即可，不实现 Web 新功能。

## Final validation commands

完整命令的最终执行结果已记录在 research/final-acceptance.md（196普通/23实际named及双产物检查）；以下保留可重现命令：

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test --seed 631927
# 使用临时可信 cookie/唯一节点名，不在日志/终端回显 cookie：
elixir --sname <isolated-test-node> --cookie <securely-provided-cookie> -S mix test --only distributed --seed 631927
mix credo --strict
mix dialyzer
mix sobelow
mix xref graph --format cycles
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_daemon --overwrite
BEAMLET_BACKEND_BUILD=1 MIX_ENV=prod mix release beamlet_cli --overwrite
bash scripts/deployment/check-release.sh
bash scripts/deployment/check-local.sh
git diff --check
```

- 新检查脚本应覆盖两个复制产物：daemon 三种启动选择、CLI interaction、长名服务启动/RPC/stop、默认服务端口/临时控制端口，真实 stdin 命令流与两个独立客户端重新附着。
- 保留 Web 未配置 SECRET_KEY_BASE 的 prod 启动失败检查、Web CSP 测试与本地 HTTP fixture 测试。
- 对变更源码主动运行 LSP 路径检查；不可用/超时列为不确定，不用空 session cache 声称干净。
- 单独记录普通/distributed 实际数量、编译、既有 PLT 分析/刷新情况和复制产物哈希。测试失败不得通过重放业务/放宽断言掩盖。
- 本机 peers 不等于物理多机；deterministic/fixture 不等于真实付费 provider。不得无授权 SSH/部署/付费调用。

## Gates and rollback

- 每个子任务 review 通过后才向依赖者交付接口；若 shared contract 变动，重跑已受影响子任务回归。
- 临时移除旧 release 后直到 CLI 完成前，check-local 的双产物总门禁可以标记“后续交付”，但当步普通/相关 named 测试不能破坏。
- 停止本轮写入、保留 diff，精确撤回本子任务更改作为回滚点；不执行 destructive git 操作，不覆盖用户已有 staged changes。
- 最终 spec 与父 AC 验收已完成，分组提交提案见 research/final-acceptance.md；提交前必须获得用户确认，不自动 push/amend。归档/journal 仍待授权，不运行其自动提交脚本。
