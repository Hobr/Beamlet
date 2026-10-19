# Agent Core：纯事件归约与继续策略

Core 从显式数据计算 Agent 控制状态、来源绑定上下文及继续决策；不启动 Agent、Runtime、Repo 或模型进程，无 Application 回调。直接依赖 Harness 中立校验与 Jason；Harness 的传递 Req 依赖不表示 Core 会联网。存储 envelope、摘要/所有权/闭包验证、事务、派发、资源退役与不确定执行处理仍由 Agent 适配层负责。

在仓库根目录使用 `nix develop`（OTP 29 / Elixir 1.20），首次 `mix deps.get`，再进入 `iex -S mix`；以下纯调用不需要数据库或模型服务：

```elixir
alias Beamlet.Agent.Core.{Context, Decision, Reducer}
id = "12345678-1234-1234-1234-123456789abc"
created = %{
  "id" => id, "scope_id" => id, "seq" => 1,
  "schema_version" => 1, "type" => "agent.created",
  "payload" => %{"definition_version" => 1}
}
{:ok, control} = Reducer.replay(Reducer.new(id), [created])
{:ok, %{request: %{"messages" => []}}} = Context.build(control, %{}, [])
:idle = Decision.resume("await_input")
true = Decision.safe_fork?(control)
```

Reducer 接受规范化版本 1 事件，检查同 scope、连续序号、首条创建、turn/step/ordinal、暂停及角色继续位置。非法历史为 invalid_history，版本不支持为 schema_unsupported。`new/1` 原样保留 identity，不替调用者验证 UUID。input.accepted 要求瞬时 input_digest，由存储适配器按既有规范编码计算；控制只保存引用，不存输入/请求/回复正文，不自行散列或改变持久化版本。payload 从自身根计算深度 32，不把 event/replay 容器算入。继承引用要求精确字段、规范小写 UUID/摘要、正数序号与匹配的 evidence_resolution，但实际内容读取与摘要验证仍在外层。

`Context.build(control, catalogue, materials)` 返回 request/sources/policy。材料 source 必须绑定下一次 timeline 精确选中出现，携带 input 或 operation，可选 resolution；缺失、额外、乱序、替换及身份/决定关联错误均拒绝。timeline 显式重复选择同一来源仍可处理。存储适配器在提供材料前校验摘要、所有权、继承闭包和 accepted/prepared 关系。历史模型回复按其操作的历史目录验证，最终请求按当前目录验证。`complete_boundary/1` 只检查完整工具配对，不按新 schema 重验旧参数。

增量接口为 start/1 → 逐项 append/2 → messages/1 或 finish/2。适配器验证并转换一项后才读下一项，使非法回复或超限前缀优先失败，后续来源不会被预读。消息逆序暂存，精确计入 JSON 括号、逗号和转义，最多 128 条/1 MiB，拒绝增长而不驱逐。完成所有来源后才做完整请求验证；不完整工具前缀不能当完整请求。materialize/2 只转换材料，finish/2 才检查当前目录/请求。材料容器不消耗各 description/accepted Result 自己的深度预算。

不确定、取消、deadline、unknown 接受结果没有明确 resolution 时不能转为普通观察。显式决定被编码为 accepted_status 与 explicit_decision，不改原 Result。reply/1 只是存储形状转换，后续仍需 Model 语义校验。

Decision 只分类：text → completed，tool_calls → reply_recorded；resume 返回 idle/advance/replay_reply/pending 或 unsupported_continuation。resumable? 包含 blocked，但 resume 不直接推进 blocked。safe_fork? 仅检查无 pending/blocked 及允许的完整位置，不能证明外部环境停止或完成存储闭包验收。宿主继续保留固定 prepared request、事务与生命周期规则，不能将重放误作重执行。

在仓库根目录验证纯逻辑和适配层顺序：

```sh
mix test --no-start apps/beamlet_agent_core/test --seed 631927
mix test --no-start apps/beamlet_agent/test/beamlet/core_adapter_test.exs apps/beamlet_agent/test/beamlet/context_read_order_test.exs --seed 631927
elixir scripts/quality/check-contracts.exs
```

现有[英文说明](README.md)保留，英文补全等待中文阶段验收。
