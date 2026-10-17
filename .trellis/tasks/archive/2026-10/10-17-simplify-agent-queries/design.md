# 简化 Agent 查询设计

## 1. Scope and design decision

需求唯一来源prd.md，R4记录用户接受的语义变化。目标是删除发现专用传输状态机而非建立新服务。一个紧密耦合实现任务：传输移除、装配和回归共同交付，不能先删Endpoint再留坏测试；清理是验收后的顺序收尾，不作为可提前实施子任务。

前置证据：../../../10-17-query-transport-research/research/report.md、otp-paths.md、quality-review.md。现代rpc.call委托erpc；超时放弃响应不是取消执行。旧Endpoint kill可导致Agent死亡。这些研究文档保留，不依赖其results/experiments作为新产品测试。

## 2. Smallest change seam

- Agent.Discovery：继续拥有输入校验、安全身份投影、真实Ref读取及错误归一化；移除自定义消息协议；本机执行与远端执行共用一个有限只读入口。
- Agent.AuthoritySupervisor：仅删Endpoint子项；Registry/Resources/Delegations/Agents仍one_for_all，原身份岛不变。
- Node.configuration：删除非authority的Endpoint装配；无需interaction/executor常驻身份查询进程。
- Node.Agents：仅聚合、并发、deadline和结果上限。保留可信已连接筛选，不让Agent依赖Node；若有必要小幅调整预算传递/退出处理，不趁机重构其他调度。
- 不增加查询监督树、TaskSupervisor、watchdog、远端cancel协议、全局配额/持久索引或新依赖。当前查询的唯一业务等待是有限GenServer.call；不是任意不合作回调执行。若实施发现另有无界阻塞，先定位已有有限OTP能力，确需扩展才回到规划，不再默默加复杂框架。

## 3. Public and internal interface

公共接口不变：

```elixir
Beamlet.Agent.list(authority)
Beamlet.Agent.lookup(authority, id)
Beamlet.Agent.lookup(%{authority: authority, id: id, pid: expected_pid})
Beamlet.Node.Agents.discover(trusted_nodes)
```

list返回authority/id/pid descriptors；lookup返回真实Server Ref；discover返回 agents/failures/complete 信封。既有错误invalid_query/not_authority/not_found/unavailable/timeout/stale_agent/limit保留。调用时身份是时点观察，后续可失效；descriptor检查expected PID；显式authority+ID选择当前实例；saved Ref不变、不重绑。

内部需要远端可调用的有限入口（例如Discovery.query_local(query, budget_ms)，最终命名可调整），仅接受list或带合法id/expected PID的lookup；budget为1..5000相对毫秒。该入口验证参数、用远端本地monotonic创建deadline，不接收其他VM的绝对时间，不执行任意MFA/opts。内部远端入口不是新的用户可配置协议。

## 4. Query data flow and deadlines

```text
Agent.list / lookup
    → 校验参数、分配本地5秒deadline
    → 本机：有限只读入口
    → 远端：已连接预检查 → erpc.call(固定模块/函数，剩余预算)
                                  → 远端校验、Registry投影 / Server :ref
    → 安全结果或静态错误
```

本地调用可保留现有一次Task.async_stream隔离以防caller被查询异常带崩/响应污染；不手写第二套worker状态机。本地deadline应在helper启动前创建，等待不反复重置。helper等待超时可被OTP任务控制器结束，远端erpc进程不与Agent link。

远端函数用收到的有限预算创建自己的deadline，Server读取只等剩余时间；无infinity等待。远端预算从实际执行入口开始计算，可能晚于调用方deadline；已批准允许这类有限尾部执行，不伪装成跨VM绝对截止。erpc超时/连接失败/退出/undef等映射固定安全原因，不返回栈、原始异常、凭据。标准分布式信号/调度可能延迟timeout，不宣称硬实时。

列表直接Registry安全身份select，不逐Agent快照；最多128身份及完整返回1MiB上限。lookup核对authority/id/pid/incarnation，不读私有state。调用方丢失后有限查询仍可能完成、已入Server邮箱的ref消息仍可能处理，这是已批准的只读语义。

## 5. Authority detection and failure isolation

- 无Endpoint后，authority能力以现有Agent基础设施判定，不依赖Node或宿主配置，不新建标记进程/第二注册表。
- 当前VM未运行authority，返回not_authority；若authority已存在但Registry/Server查询失败，返回unavailable/timeout。检测及查询有竞态，不能把中途设施损坏当成成功空列表。
- 普通已加载库的非authority VM可以回答not_authority；远端没有代码、VM不可达返回unavailable，不假称完整空authority。
- Registry PID/注册来源的检查须与读取一致，避免Registry重启前后混拼Ref；原Registry丢失会停止Agent，继续保留回归。
- 删除专用查询进程从根源消除其one_for_all崩溃入口。查询执行进程退出不应触发authority监督树重启；测试核对Agent和Registry/Agents监督PID。
- erpc库级加载不启动任何业务角色，未来Web复用同API，无新启动配置。

## 6. Resource and connection contract

- 保留最多32个明确可信节点、8个聚合并发、共享5秒总接收预算、128身份/authority、1MiB完整结果；partial failures不伪装为空集。
- Endpoint的256 pending/active和心跳租约是旧协议资源，随协议删除，不建立全VM并发准入服务代替它。每次聚合和每次查询有现有边界；不承诺无限调用方下的全节点总查询配额。
- API入口发现目标未连接时仍unavailable，不主动扫描/建连；筛选后断线允许OTP自动连接。不改变VM全局dist_auto_connect或daemon/CLI显式connect策略；文档不得再声称逐消息绝不重连。
- 无查询自动重试、无业务重放、无Agent重新创建。OTP重建连接不等于应用重试查询。

## 7. Files, tests and documented supersession

预计变更：
- apps/beamlet_agent/lib/beamlet/agent/discovery.ex：简化传输和有限远端入口。
- apps/beamlet_agent/lib/beamlet/agent/discovery/endpoint.ex：删除。
- apps/beamlet_agent/lib/beamlet/agent/authority_supervisor.ex：删除查询child。
- apps/beamlet_node/lib/beamlet/node.ex：移除非authority查询child。
- apps/beamlet_node/lib/beamlet/node/agents.ex：仅必要的预算/错误路径适配。
- Agent discovery_test、Node discovery_distributed_test及角色装配测试：替换旧协议内部测试，保留公开行为/故障证据。公共API facade文档按需更新。
- CLI/daemon依赖共享接口，运行相关回归；仅若有真实旧Endpoint引用才改它们，禁止无关terminal/deployment重构。
- .trellis/spec/backend/agent-orchestration.md、directory-structure.md、index.md，必要的backend-release.md/README：说明新调用/失败/连接契约。旧发现/父任务的旧设计不整篇重写；只在当前仍被用作规范的相关任务增加明确“由本新任务覆盖”的说明，避免后续误把旧要求恢复。
- 本任务保留简洁验证报告/决策摘要。原研究report/质量结论为历史实验事实，不改成新实现测试通过。

测试重点：
1. 本机/远端正常list/lookup，非authority/无代码/断开、ID复用stale_agent、关闭not_found、同名authority、attach不input、不泄漏。
2. 暂停真实Agent，查询timeout/caller exit后远端有限结束且Agent PID/incarnation不变，真实本地helper退出、晚回复被弃；不再要求300ms、无过期准入或Server邮箱无ref。
3. 查询执行进程异常kill对照：Agent、Registry/监督PID不变，恢复后正常query；测试不以不存在的Endpoint被kill冒充故障。
4. 已断开目标入口拒绝；预检查后断线允许标准OTP行为，不再断言绝不nodeup；保留可信输入和无无界atom。
5. 32/8/5秒/128/1MiB界限、10慢节点聚合总预算及partial；控制面standard_io、事件屏障/本地trace优先，不依赖研究目录或新增产品test开关。
6. 七角色组合/依赖加载空宿主/CLI重新附着/daemon启动与原Registry身份失效。

## 8. Rollout and user-confirmed cleanup

传输从自定义改为固定erpc查询函数，库版本应配套更新；不增加混合版本协商/回退旧Endpoint路径。不保证旧客户端能调用新节点或新客户端能发现旧节点；旧saved Ref PID/incarnation若业务进程未重启其语义不因此改变，部署重启本身仍使Agent失效。

先完成实现/必要测试/独立review/spec同步，向用户报告实现已可验收；不commit，不在测试通过时自动删旧证据。

仅收到用户“新任务完成/验收通过”等明确确认后：
1. 先把两轮run IDs、版本、98场景及核心结论、独立PASS、已知限制保存在旧research/report与新验证摘要；说明摘要是历史记录。
2. 删除且仅删除旧任务根下results/、experiments/与仅服务这些目录的.gitignore例外；盘点时若其他中间文件不明确则保留，禁止扩展清理到其他任务/全局subagent artifact或构建目录。
3. 修正旧任务prd/design/implement、research各文档对已删路径的Markdown链接和复现命令：用文字说明清理日期/用户确认/原文件不再随仓库提供，保留外部一手链接/结论；不伪造可复现实验仍在。
4. 搜索剩余相对链接、确认两目录不存在、产品测试不引用它们；新任务AC7此时才勾选。不commit、不自动archive，继续遵守用户不提交。

回滚通过定向恢复本任务产品变更，禁止reset/clean误删旧未跟踪研究；清理完成后不承诺恢复已删除的原始文件。
