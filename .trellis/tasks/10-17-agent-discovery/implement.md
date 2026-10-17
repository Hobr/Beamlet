> Historical transport requirements are superseded by [simplify-agent-queries](../10-17-simplify-agent-queries/design.md): finite local/erpc reads, no Endpoint or leases, and standard OTP reconnection after the entry precheck. Public identity/attachment contracts remain.

# Agent 查询实施计划

## Prerequisites

node-library 已通过检查，实际顺序在 daemon 后、CLI 前；daemon 非本机接口测试的强制依赖。进入实现前读取父 design 第5节并 start 此子任务。

## Steps

- [x] 明确共享返回类型/错误和预算常量，一处定义，调用者不自行解析私有 Registry/state。
- [x] 加本机 list/lookup 测试：ID输入边界、非 authority、未找到、正确 PID/incarnation、安全投影。
- [x] 实现 Agent 业务所属接口及显式 authority 的有界远程调用，不添加 Node 依赖。
- [x] 加同 ID 两 authority、ID复用、关闭并发、lookup 期间 Server 阻塞、旧 Ref 不重绑的测试。
- [x] 在 Node 添加可信已连接节点聚合；覆盖32节点/8并发/5秒预算/1MiB信封和 invalid_query/partial。
- [x] 实际 peer 分区/退出与 caller DOWN，先断言查询/helper 在有限预算内结束，再恢复被暂停设施，证明无迟到控制/重建。
- [x] 输出不包含 binding/credentials/options/history；记录接口/限制并交付 CLI。

## Validation and rollback

- mix format --check-formatted；mix compile --warnings-as-errors；相关 Agent/Node 普通测试及 umbrella mix test。
- 以隔离命名 VM 和安全 cookie 运行 distributed 查询/现有执行回归，记录实际执行数。
- mix credo --strict；主动 LSP 改变文件；git diff --check。
- review 必须检查 RPC 总预算而非每目标预算、结果完整性和 helper 清理；任一不足不能交付 CLI。
- 改动仅 Agent 查询与 Node 聚合；不改变 Agent 模型循环、创建语义和 Runtime 路由。若共享契约需改，更新父设计并重审；精确回滚查询差异而非重置仓库。

## Transport amendment execution

- Implement Agent-owned bounded handshake endpoint, AuthoritySupervisor placement,
  and non-authority Node placement (parent approved internal source expansion).
- Test identity/failure contracts before source implementation; verify actual DOWN
  before resuming suspended Servers/endpoints, and no-connect paths on named VMs.
- Remote cleanup is bounded by heartbeat lease, not instantaneous cancellation
  across partitions. Preserve original failed/final validation logs separately.

## Implemented CLI handoff (accepted after admission repair)

Parent accepted the repaired candidate after independent READY review. See
research/review-disposition.md for authoritative repaired validation and hashes.
The initial validation/freeze paragraph below records the historical candidate;
it is superseded by that disposition, not current repaired-candidate evidence.

All implementation steps above are complete. Public contracts:

```elixir
Beamlet.Agent.list(authority_atom)
# {:ok, [%{authority: authority_atom, id: utf8_binary, pid: real_pid}]} | {:error, static_reason}
Beamlet.Agent.lookup(authority_atom, id)
# {:ok, real_server_ref} | {:error, static_reason}
Beamlet.Agent.lookup(%{authority: authority_atom, id: id, pid: expected_pid})
# same; replacement PID => {:error, :stale_agent}
Beamlet.Node.Agents.discover([trusted_node_atom, ...])
# {:ok, %{agents: descriptors, failures: %{node_atom => static_reason}, complete: boolean}}
# malformed/duplicate/>32 target set => {:error, :invalid_query}
```

Resolve names through Cluster.authority/2 using explicit trusted configuration;
queries never atomize strings or connect. Local discovery inclusion follows
Cluster.connected/1 (alive local VM), whereas Agent.list(node()) also works on an
unnamed standalone AuthoritySupervisor. A Node without authority responds
not_authority; missing endpoint is unavailable locally/unconnected, timeout if a
connected target cannot respond. Unknown ID is not_found. Query IDs are1..128 UTF-8
bytes. Descriptor must have exactly3 keys; Ref is never accepted as a descriptor.
Explicit authority+ID selects the current instance; descriptor checks expected PID;
old Ref retains original PID/incarnation and is never rebound. A removed ID with
no replacement returns not_found. Static reasons: invalid_query/not_authority/
not_found/unavailable/timeout/stale_agent/limit. No model/config/credential/history
projection, implicit input, ownership transfer, recreation or retry.

Each Agent query has one5s receive budget. Aggregation max32 distinct nodes,
max8 concurrent, one5s total receive deadline for all queued targets, full
`{:ok, result}` external_size<=1MiB;16KiB reserved for future failure map entries.
Oversized authority result is rejected whole with limit, never truncated.
Empty requested set completes. complete covers the requested set only; observed
liveness is eventual and subsequent Ref commands can fail. Endpoint cap256 pending
+ active, max128 identities per authority. Passive offer5s, confirmation required;
controller5s and250ms heartbeat lease/50ms renewal; remote cleanup normally<=300ms
plus scheduling after local helper loss, not instantaneous partition cancellation.
Read amended design.md and research/implementation-evidence.md for lifecycle/audit.

Final gates: format, warning-fatal compile, strict Credo,181 ordinary tests and22
actual named distributed tests (seed631927), active LSP10/10 files no diagnostics,
whitespace and dependency/source searches passed. Parent independent check remains
unchecked/pending. Product/test/spec frozen manifest:
`/tmp/discovery-frozen.sha256`, SHA256
`60c099d16c12e8ce2c4e181d60f89222a2f5a1919585ba17ca1da24362873ce1`.
Do not edit frozen candidate without explicit follow-up authorization.
