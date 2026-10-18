# 执行与集成计划

## 顺序与门禁

1. 规划审阅获批后，启动 A 子任务，不启动父任务做全部代码。
2. A：schema/codec/事务/双库契约；完成后记录真实通过/失败/未跑。
3. B：Runtime prepare/accept 与 journal 协议适配；验证本地与 named peer。
4. C：Agent reducer/上下文/恢复/消费；验证重放等价和零副作用。
5. D：fork/导出/宿主/已有交互，执行全范围端到端、故障和 release 验收。
6. 父任务核对 PRD AC1–AC7 全部证据，更新实现状态与迁移操作说明，再提交/收尾。

子任务依赖是执行顺序要求，不由 parent/child 自动调度。切勿并行修改相同 Storage/Agent 文件。每次派发 prompt 首行使用 task.py current 对应的子任务路径，先读该子 PRD/design/implement 与 context manifests。

## 验证命令

全部从 umbrella root 执行；数据库变量指向隔离的本地 PostgreSQL 集群，使用 fixture 创建并删除自己的测试库，不连接用户现有库。

- mix format --check-formatted
- mix compile --warnings-as-errors
- mix test apps/beamlet_storage/test （需要 BEAMLET_PG_SOCKET_DIR，可选 BEAMLET_PG_PORT/BEAMLET_PG_USER）
- mix test apps/beamlet_runtime/test apps/beamlet_agent/test apps/beamlet_node/test apps/beamlet_app_server/test
- mix test --seed 631927
- elixir --sname beamlet_durable_check --cookie beamlet_durable_check_cookie --erl "+S 2:2" -S mix test --only distributed --seed 631927
- mix credo --strict --all
- mix dialyzer
- mix sobelow
- mix gettext.extract --check-up-to-date
- bash scripts/deployment/durable-e2e.sh
- bash scripts/deployment/check-release.sh（先读取脚本参数与前提，完成受影响 copied/named release 组合）
- BEAMLET_BACKEND_BUILD=1 mix compile --warnings-as-errors

按子任务选择针对性门禁，最终 D/父任务执行全范围。命令失败、PG 缺失、named peer 未实际执行、LSP 超时均记录，不能记为通过。Credo 清理旧任务的“禁止改变行为”仅适用于当时 refactor，本次允许经 PRD 明确授权的模型/Schema 变化，不允许压制 lint 或删除测试行为覆盖。

## 故障与回退

每个准备/claim/start/terminal/accept/consume 边界用可控 barrier，记录 stable ID 与 Handler 外部调用计数；不是靠 sleep 碰运气。事务失败断言零部分事实，进程/VM 中断断言未知不重发。SQL/codec 限制及恢复内存预算验证恰好边界与超限。

不破坏已有库；用隔离新格式数据集。中间子任务不得上线或声称全伞通过；最终无旧模型回退路径。若契约无法保持本地/远端正交或需要自动重发才能成功，回到设计，不用兼容层/timeout 增大掩盖问题。
