# CLI 会话与 release 设计

## Prerequisites and ownership

依赖 node-library、agent-discovery，跨宿主验收使用 daemon。遵循父 design 第3/4/5/6/7节，需求 R4/R5/R6/R7/R8/R9。

CLI Application 未启用时只提供空监督树；cli_runtime.exs 显式启用 interaction Node 和 standalone session runner。输入读取与退出 VM 只属于 standalone 路径，不阻塞 Application.start，不影响单测/嵌入调用。

## Modules and flow

Command.parse(line) → 结构化动作 → Session dispatcher → Cluster/Agent/Node.Agents → Renderer。
Parser/renderer 可独立测试，Session 的 IO/退出策略可注入。CLI.Client 承接已迁移的 watch，接收与 ack 必须同一 sink；取消/退出使用 monitor/after 清理，不把 raw spawn 当所有权方案。

Session 仅保存有界 alias→Ref 映射（128），命令与边界遵循父 design。create 从绝对 operator-owned Config 文件读取 :beamlet_cli, :agent_options；没有通用 eval，不回显配置、异常或凭据。配置是可信代码这一限制要在 help/runbook 明示。输入不截断，超出当前 Agent/Operation 限制由原校验明确拒绝。

agents 查询可列全体已连接可信目标或指定 authority；attach 使用 authority+ID，可命名本地 alias，不默选同名。新的 CLI 无需拿到旧会话内存即可 query 真实 Ref。列表 descriptor 用 expected PID 做失效检查，不能刷新旧别名到同名新实例。

status/input/stop/close 使用当前 Ref；attach 返回 snapshot，不隐式执行 input。watch 最多256事件/60秒接收/每事件4096 codepoints，初版同步有界等待即可。watch结束不是 Agent结束。detach/EOF/quit 只取消观察/本地引用，显式 close 成功才清除相应条目。多客户端并发 input 使用已有 busy 结果，不新增锁或 ownership。

## Packaging and migration

添加独立 beamlet_cli release/runtime 配置，保留 backend selector。release 前台 start 直接提供 stdin shell，不要求 IEx，不引入 escript。CLI 产物不含 daemon/Web；daemon 构建和 CLI 构建均从根声明，不能因 umbrella 编译集合包括两者就让闭包同时带上两宿主。

扩展 check-release/check-named/check-local，验证 CLI stdin/EOF、跨两次 CLI 进程重新附着，daemon三个启动配置与两产物闭包；端口和进程清理由唯一名字/临时目录及有限 deadline 负责。保留迁移的原 CLI、HTTP fixture、workspace、stop/loss回归；不改历史归档文档。

## Risks

真实 stdin 可阻塞、secret 可能被异常 inspect、查询部分结果易被误读、旧Ref可失效。分别由独立 runner/有限控制调用、安全错误投影、complete/failures和显式重新 attach 处理。进程退出不代表上游请求回滚，不给出计费停止承诺。

## Owl presentation (user-directed revision)

Installed Owl0.13.1 owns help/nodes/agents/identity/status tables (Owl.Table.new),
terminal output (Owl.IO.puts) and bounded display (Owl.Data.truncate/to_chardata).
Explicit unbounded table width with bounded cells prevents narrow terminals from
omitting authority/ID columns; cells wrap rather than hide identity. At most8
identities per discovery page, with total/shown/completeness/failure counts;
failures cover at most32 targets. Snapshot fields use safe domain projections.
Application grammar, dispatcher and alias identity remain CLI responsibilities.
Runner's minimal byte transport is required because Owl.IO.input uses unbounded
gets, normalizes/trims text and recursively retries required input/EOF; it cannot
preserve executable input bytes or enforce a hard allocation bound. Piped stdin
stays prompt-free, IO/exit stay injectable, and watch uses the same sink.

### CLI review repair: Unicode input and complete identity traversal

Runner reads one raw byte with IO.binread/2 against65536 before retention.
For a terminal only, the exclusive stdin reader temporarily sets device encoding
Latin-1 to preserve original UTF-8 bytes (Unicode decoding otherwise replaces
malformed bytes); an after block restores the original encoding before output or
callbacks, including failure/EOF. Concurrent readers on that owned terminal are
unsupported. Pipes and injected nonterminal devices never change options.
LF is the delimiter; all preceding text and partial EOF are preserved. Native
read errors, invalid UTF-8 and overlong lines terminate with status1; EOF/quit
exit0. Executable input is never replaced or executed as a truncated prefix.

`agents [authority]` replaces one retained bounded discovery result (the existing
1MiB query bound); `agents-page N` traverses it without another query. Pages have
at most8 rows sorted by authority string, ID bytes and PID string. Query complete
refers only to requested targets; page/count describe display completeness.
Discovery remains an eventual, non-atomic cluster observation. Agents may change
or die after capture; refresh explicitly with agents, then restart traversal.
There is no implicit requery/retry and attaching still resolves the current ID.

Identity cells use `id64:` plus unpadded Base.url_encode64 UTF-8, accepted by attach
without evaluation. Copy the whole token and supply a safe explicit alias:
`attach host@local id64:dHdvIHdvcmRz a` attaches ID `two words`.
Simple nonreserved ASCII IDs remain accepted literally. To address a literal ID
starting with id64:, encode the entire ID. Decoded IDs retain the shared valid
UTF-8 1..128-byte contract, including whitespace and terminal controls. Tokens
are at most177 bytes; commands including encoded arguments still obey65536 bytes.
No shell grammar/eval or shared Agent ID restriction was introduced.

Installed Owl uses Ucwidth for CJK/emoji/combining terminal column measurement,
wrapping and truncation; actual beam behavior and copied closure are checked.
The independent4096-codepoint watch limit remains distinct from display width.
