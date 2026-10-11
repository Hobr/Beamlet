# SPEC: lease 与权限

状态: 草案. 记录 Q19、Q28、Q46-Q49、Q52-Q56 已确认规则. 具体时间精度、存储字段与最终 Interface 尚未完成.

相关文档: [核心状态机](core-state-machines.md), [Handler 契约](operation-handler-contracts.md), [RFC 0001](../rfc/0001-core-boundaries.md).

## 1. 三种不同权限

| 概念 | 用途 | 不保证什么 |
|---|---|---|
| Worker lease | 临时领取、启动申请、续租及相应协调权限 | 不证明外部操作已停止 |
| Start Authorization | 为特定 Execution 与 incarnation 持久化的启动许可 | 不证明真实开始或恰好一次执行 |
| Execution 结果资格 | 正常结果是否可以成为 Outcome 候选 | 不等于 lease 有效或报告绝对真实 |

报告接收与 Outcome 接受分别验证. lease 到期不自动撤销当前 Execution 结果资格; 明确替代/撤权后旧尝试不直接赢得提交, 但证据仍可保存.

## 2. 时间依据

- 由 Authority 在处理原子命令时提供时间, 领域规则接收显式输入.
- 不以 Worker 报告时间或跨实例裸 monotonic 值判定持久到期.
- PostgreSQL 使用权威数据库当前时间, 不将长事务起点 now 视为验证当刻.
- SQLite 使用权威操作路径的当前 VFS 时间, 不把不同主机 UTC 视为同一时间源.
- 权限验证点和采样必须在具体 Adapter 中明确, 不使用进程外先验读取代替原子检查.
- 保持事务短小, 不在事务内调用外部 Handler.
- 数据库时间可能前跳或后跳. TTL 不承诺真实经过时间的精确上界, 更不证明外部操作终止.
- Worker 可以用本地计时安排心跳和提示, 但不推翻 Authority 裁决.

待定: 时间单位、精度、采样点、取时方法、检测异常的诊断和测试配置.

## 3. generation 与 incarnation

- Execution 领取权限有持久 generation, 由 Authority 分配并绑定 Worker incarnation.
- 重新领取使用新 generation, 普通续租不改变 generation.
- generation 不重置复用. 计数表示与耗尽处理待定, 不允许通过复用旧代恢复旧资格.
- 临时控制请求必须匹配当前 generation 与 incarnation, 并满足相应 lease 条件.
- 旧代不能续租、申请启动或执行旧 lease 保护的动作.
- 报告不因携带旧代就一律丢弃; 按来源、身份及独立结果资格验证.
- generation 只在相应权威历史内提供并发资格依据, 不跨两份独立数据库自动 fencing, 也不自动成为外部服务的资源 fencing token.

## 4. 到期与续租

验证时, now < expires_at 才尚未到期. now == expires_at 也算到期.

临时控制资格至少要求:

1. 请求匹配当前 incarnation 与 generation.
2. 当前代没有已提交的到期/撤销事实.
3. Authority 验证时间仍小于 expires_at.
4. 满足命令的 Intent / Execution 守卫.

Authority 确认到期或撤销必须持久化失效事实. 即使墙钟回拨到 expires_at 之前, 此代不能复活.

若墙钟后跳发生在权威确认之前, 仍可能延后检测. 前跳也可能提前触发失效. 两者不单独授权危险重试.

续租必须在原子边界验证当前代、incarnation 与未失效条件. 失效后取得权限需要新领取决定和 generation, 不表示可以重新执行同一尝试.

## 5. 到期后的处理

- Prepared 且 Authority 原子确认从未授予启动许可: 旧领取资格失效后可由新 Worker 领取同一 Execution.
- StartAuthorized 且缺少可靠结果或 Pending: 可进入 Unknown, 保留当前结果资格, 等待迟到证据或协调.
- Waiting 有合法可恢复登记: 不只因为 Worker lease 到期就变 Unknown.
- 已授予启动许可的新 incarnation 不继承旧许可重新调用 Handler.
- 再次执行需要安全的新 Execution, 原子切换当前关联; 不因到期自动重试.
- 不用 Worker 声称未收到授权或未执行代替权威记录.

## 6. 同一 Intent 的并发边界

领取、续租、到期/撤销、启动、替代尝试和影响结果的报告必须满足对应原子守卫. 与同一 Intent 结果判断有关的决定不能使用被并发变化推翻的快照.

具体采用锁、revision 条件或组合机制由 SQL Adapter 决定. 不要求不同 Intent 全局串行, 不依赖单个 GenServer 独立保证正确性.

## 7. History

必须记录关键事实: 领取/Worker/generation 变化、权威确认到期/撤销、启动授权、失联 Unknown、替代尝试与安全依据.

普通心跳和普通续租默认不逐条进入领域 History, 但当前 lease 更新仍需原子验证. 可以使用独立诊断日志与指标; 不能靠重放 History 恢复全部续租.

## 8. 重启与迁移

普通 Coordinator 重启且权威数据库未迁移时:

- 重新读取并验证已提交状态.
- 不默认撤销所有远程 Worker lease.
- 新 Worker incarnation 不继承旧启动许可.

正式 Authority 迁移时:

- 新 Authority 激活前使旧临时 Worker lease 失效.
- 保留 Execution、启动证据、当前结果资格、幂等上下文及 Pending 完成关联.
- 不把已授权尝试重置为 Prepared 后再执行.
- 合法迟到报告与回调仍可验证, 不复用旧临时控制资格.
- 必须另行满足一致切点和旧 Authority 撤权, 本文不构成完整迁移协议.

## 9. 最低测试场景

1. 验证时间等于 expiry: 拒绝以尚未到期权限操作.
2. 到期事实提交后墙钟后跳: 旧代不复活.
3. 后跳发生在确认前: 可延后检测, 不能同时授予冲突权限.
4. generation 切换后旧续租/启动申请到达: 拒绝旧代控制.
5. 续租与到期竞争: 按原子边界裁决, 不产生相互矛盾的有效权限.
6. lease 到期后迟到成功: 未明确撤销结果资格时仍可验证接受.
7. 已授权失联: 不自动让新 incarnation 再调用.
8. Waiting Worker 到期: 不重复创建外部请求.
9. 普通 Coordinator 重启: 不无端使远程 lease 全部失效.
10. 正式迁移: 临时权限失效, 外部证据和合法完成关联保留.

这些是完整协议和后端的验证要求. 首个 [Quint 模型](../quint/README.md) 已运行整数时钟、generation、到期后回拨、迟到报告和普通重启的抽象场景. 时间采样精度、真实数据库故障、完整续租/到期事务和正式迁移仍未验证; 不能将整张清单视为实现测试通过.

## 10. 查询的安全边界

- not_found、尚未开始或暂无结果默认只构成协调证据, 不单独授权危险重试, 不将未知尝试自动标为确定结束.
- 不可重复操作的安全重试需排除旧尝试或在途请求以后执行, 或以可靠外部幂等/fencing 覆盖重复窗口, 或调用方明确接受重复风险.
- 外部查询现在未发现操作不能排除已获授权旧 Worker 稍后发送请求; 判定依据必须包含协议条件.

## 11. 仍需确认
- 启动请求身份、重复响应和 Worker 实际启动一次的协议.
- 临时协调动作、generation 存储及最终原子命令 Interface.
- 数据库配置、真实故障/掉电保证和迁移中断恢复.
