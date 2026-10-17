# 查询传输隔离实验发现（实验 seam，非最终选型）

> 留存状态（2026-10-17）：用户已接受后续 simplify-agent-queries 实现，按约定清理本任务的 results/、experiments/ 及专用 .gitignore。原始记录、失败日志、源快照和实验脚本不再随仓库提供，不能按原命令复现。本文保留历史结论及来源，不冒充仍可读取的原始证据；涉及“当前/现有”的描述均指研究时基线9657d2a。后续实现与验收见[已归档实现任务](../../archive/2026-10/10-17-simplify-agent-queries/prd.md)。

## 摘要与证据等级

2026-10-17 在基线 `9657d2a`，运行 **OTP29.1.2 / ERTS17.1.1 / Elixir1.20.4** 的真实命名 disposable VMs。最终 run：**`20261017T122252-5c3d06fc`，退出码0，98个独立 peer 场景全部完成、98个 peer 均清理**。所有关键故障/竞态组合各使用3个新VM独立重复；另有控制smoke和96次小规模查询批次。结果是同一物理机上的功能/故障证据，**不是生产性能、跨物理机、硬实时或无限次竞态证明**。

事实和推论必须分开：

1. **源码+实测**：本机现代 `rpc.call/5` 委托 erpc；暂停 rex 不阻塞现代rpc/erpc正常查询。不能再把现代rpc统称“都排在rex里”。
2. **实测**：本地约121ms超时、甚至调用方已经被杀，并不停止已运行的650/900ms有限远端工作。远端最终完成并真实DOWN，不是仅凭本地返回判断取消。
3. **实测**：传统rex探针超时后，排队请求仍可在rex恢复后开始；本地caller mailbox最终为空不等于远端未工作。
4. **实测**：三类OTP传输最初断开或precheck后再断开，实际调用均重新连接。现代rpc/erpc本轮执行/回复阶段断线后未观察到回复重连；真正rex探针则观察到重连。
5. **实测**：当前Endpoint在caller loss /执行期断线后约300ms回收真实controller/worker，但**worker死亡不撤回Server里已入队的`:ref`请求**。这不是瞬时取消。
6. **实测**：直接 `Process.exit(endpoint, :kill)` 会触发authority内部one_for_all，旧Agent PID死亡；没有自动重建Agent。手动调用现有Agent.start后，实际PID/incarnation均变化。普通只读查询超时/调用方退出没有这种连带死亡。
7. **限制**：未稳定的OTP rex特征交换曾干扰快速连接切换；失败日志曾保留（现已清理），最终实验加交换完成屏障和本VM发送trace。旧失败的具体nodeup发送者未直接trace，根因归因只作源码支持的假设。

## 留存文件与复现限制

旧实验脚本、日志、raw、派生索引、源快照及逐次清理记录已按用户要求清理，不再提供可执行复现命令。保留本文场景表、PID对照及限制；源码语义见[OTP路径](otp-paths.md)，选型与生态来源见[综合报告](report.md)和[生态研究](ecosystem.md)，独立复核历史摘要见[quality-review.md](quality-review.md)。这些文档是历史记录，不是仍可读取的原始证据。

## 拓扑与观察防污染

- 同时最多 **1 coordinator + 1 peer**，每个场景结束后销毁peer。每个peer启动真实 `Beamlet.Node(roles: [:authority])`，通过标准IO boot pattern解链，与现有TestBoot一致；不使用真实集群节点名。
- 启动后、任何distribution连接前安装本次随机cookie，不输出cookie，不借用现有节点的cookie进行连接。私有epmd不查询/停止共享epmd。无模型input、无网络模型调用；Agent模型为内置deterministic且credentials为空。
- 对远端控制、恢复、worker状态、mailbox/connection读取均用 `:peer` 的 **standard_io**；断线观察窗不使用被测distribution上的RPC、remote monitor、remote IO。Facts监控的是**本VM** worker，节点事件来自本地monitor_nodes，均不自行建连。
- 正常连接先等待双端rex特征交换完成。两端本地trace rex observer send，避免把OTP基础设施待处理消息误认成查询动作。
- precheck竞态用消息屏障：收到“本地已连接检查为true”的确认后才断线，再放行实际调用。Endpoint的precheck/send_safe原语与public API分开标注，未修改/解释执行产品模块，**没有冒充精确冻结其私有指令窗口**。
- 正向Node.connect控制在观察窗口**结束后**执行，另有独立control_smoke新peer；不会把正向控制产生的nodeup算到无重连窗口。
- 所有耗时是某VM本地monotonic差值。Facts事件的local_elapsed_ms只用于该VM内部顺序，不与coordinator时间相减。
- 语义断言检查真实身份、屏障、进程退出、清理；重连结果本身以原始事实记录，不预设“RPC一定坏/Endpoint一定好”。

## 精确场景矩阵

以下RPC列均指 `rpc`、`erpc`、**`rex_internal`** 三个独立组；每组各3次。`rex_internal`是**OTP29.1.2非公共协议探针，不推荐用于产品**。

| 原始scenario前缀 | 数量 | 预期/控制条件 | 实际观察 | 每项限制 |
| --- | ---: | --- | --- | --- |
| control_smoke | 1 | 断线后standard_io仍可控制；显式connect阳性 | 控制成功、观察前无重连、Agent活着 | 只覆盖本机peer控制 |
| normal/{transport}/1..3 | 9 | list/lookup同真实PID/incarnation；现代路径rex暂停 | 全部返回真实fixture身份；现代rpc/erpc在rex暂停中成功 | 小列表、单Agent；正常调用无独立worker开始trace，以返回/monitor执行路径为证 |
| slow_timeout/{transport}/1..3 | 9 | 本地120ms vs 远端650ms预算 | 本地约121ms结束时远端仍活；约651ms后完成并DOWN；caller存活期间晚邮箱为空；Agent存活 | 有界函数是测试控制函数，不是任意用户函数硬时限 |
| caller_death/{transport}/1..3 | 9 | 远端start屏障后kill本地caller | caller真实DOWN；远端立即样本仍活，约901ms完成并DOWN；Agent存活 | 不包含永久阻塞/远端VM死亡；dead caller无邮箱可读 |
| suspended_server/{transport}/1..3 | 9 | Server一直暂停到远端650ms预算退出 | 约121ms本地返回、远端仍活；远端最终DOWN，`:ref`仍排在Server；恢复Server后、caller仍存活时晚邮箱为空；新lookup同ref | 取消执行不能撤回已送达消息；采样窗有限 |
| initially_disconnected/{transport}/1..3 | 9 | 完全断开后直接调用 | 三类均nodeup并成功，最终run调用2–4ms | 只证明默认配置允许连接，不覆盖禁用dist_auto_connect配置 |
| precheck_disconnect/{transport}/1..3 | 9 | 明确precheck屏障，断开后才实际调用 | 三类均重连并成功 | 是显式precheck+调用，不是原子“连着才调用”承诺 |
| disconnect_execution/{transport}/1..3 | 9 | 远端start屏障，断线后让900ms工作自然完成 | 本地约6ms报nodedown/noconnection；远端仍完成/DOWN；现代rpc/erpc未见nodeup，rex探针见nodeup；晚邮箱为空 | 干净disconnect而非丢包/半开；观察约1秒余，不是无限时禁止重连 |
| disconnect_reply/{transport}/1..3 | 9 | 断开确认后才经standard_io放行远端返回 | 现代rpc/erpc无回复重连；rex探针重连；晚邮箱为空、Agent存活 | 模拟返回前屏障，不是逐字节截断distribution包；默认协议栈 |
| endpoint_normal/1..3 | 3 | 原Endpoint正常list/lookup | 同真实PID/incarnation；active=0、mailbox=0 | 现有5秒预算保持不变，无性能结论 |
| endpoint_execution_disconnect/1..3 | 3 | Server已有`:ref`，再断线；不恢复Server就测DOWN | 实际controller/worker约300ms退出；连接仍断开；Agent活、排队`:ref`仍在 | 本地观察窗含另外200ms，cleanup_ms不包含这200ms；不是瞬时取消 |
| rex_queue/1..3 | 3 | 暂停rex到caller超时，必须证明实际队列 | 队列`$gen_call {call,...}`原文；约121ms超时前无worker；恢复后才start，约201ms完成/DOWN，caller晚邮箱为空 | 内部协议版本钉定，不可外推成公共兼容接口 |
| endpoint_timeout/1..3 | 3 | 不改5秒产品预算，暂停真实Server | 返回timeout约5000–5001ms；实际controller/worker均死，`:ref`仍在；随后恢复Server，caller晚邮箱为空；Agent活 | mailbox是在恢复后1秒采样，不证明永远无其他业务消息 |
| endpoint_caller_death/1..3 | 3 | 已入队`:ref`后killcaller，Server继续暂停 | 约300ms真实worker/controller死；Agent存活，Server队列不撤回 | 有限lease回收，不是分布式即时取消；本地caller树trace另有清理证据 |
| explicit_remote_worker_kill/1..3 | 3 | 与有限后台完成分开，显式经控制面kill远端等待worker | caller kill后远端原本仍活；显式远端kill后DOWN（reason=killed），`:ref`依然入队，Agent活 | 控制面直接kill不是可上线的取消协议，更不是“caller死则远端立即死” |
| endpoint_connections/1..3 | 3 | initial public query；precheck/send_safe屏障；已排offer断线恢复 | public返回unavailable且无nodeup；屏障send_safe=noconnect；被动offer恢复后无active/重连 | 原语屏障不是私有public函数窗口；已完成OTP握手；看不到所有未来连接来源 |
| endpoint_actual_kill/1..3 | 3 | 真正不可捕获kill；记录真实Agent/监督PID | authority岛内部Registry/Resources/Agents/Endpoint更换；旧Agent死亡、lookup not_found；显式新建后PID/incarnation变化；outer Node/Routes/Runtime与AuthoritySupervisor PID没变 | 单次子进程故障由内层处理；未测试反复崩溃超过restart intensity导致outer one_for_all升级 |
| modest_repeated_concurrent | 1批 | 每种24次、concurrency4、共96次；追踪真实helper | 全成功；148个本地traced descendants全死；Endpoint active/mailbox=0、rex monitors=0；coordinator及caller邮箱均空；远端进程126→125、本地120→119 | 粗采样含初始化/临时进程回落；不是资源零占用/负载/生产benchmark |

总计：**98个独立peer场景**。正常现代/传统组的lookup均不伪造Ref，使用当前Server已有`:ref`处理；fixture不读model私有状态。

## Endpoint故障域的具体证据

最终run的 `endpoint_actual_kill/1`（远端VM `qt_p_314254_403@handsonic`）：

| 对象 | 故障前 | kill后 / 显式重建后 |
| --- | --- | --- |
| Endpoint | `#PID<26703.181.0>` | `#PID<26703.198.0>` |
| Registry | `#PID<26703.176.0>` | `#PID<26703.193.0>` |
| Resources | `#PID<26703.178.0>` | `#PID<26703.195.0>` |
| Agents DynamicSupervisor | `#PID<26703.180.0>` | `#PID<26703.197.0>` |
| Agent | `#PID<26703.183.0>`，incarnation `#Reference<26703.1388469383.1528299521.67174>` | 旧PID实际不活；显式start后 `#PID<26703.205.0>`，incarnation `#Reference<26703.1388469383.1528299521.67242>` |
| AuthoritySupervisor | `#PID<26703.175.0>` | 不变 |
| outer Node | `#PID<26703.168.0>` | 不变 |
| Routes / Runtime.SharedSupervisor | `.169.0` / `.170.0` | 不变 |

这些是VM/节点限定的原始PID打印，不是可跨VM比较的数字。没有用 `Supervisor.terminate_child` 冒充崩溃。推论是：若产品要求“查询端点本身意外崩溃也不能杀Agent”，当前内层one_for_all故障域与该要求不一致；**不是因为Endpoint同属Agent库就必须如此**。改监督域属于后续批准的产品工作，本实验未改。

## 有限只读完成、严格取消与队列撤回是三回事

- **有限远端函数**：把只读lookup的Server等待预算放在远端函数内，caller死亡后仍可能继续，但自己能在有限时间结束。正常读不改变Agent业务状态，普通查询故障没有传播为Agent死亡。
- **严格即时取消**：本次已反证“默认RPC在caller死亡时立即取消远端”；Endpoint也有约300ms lease延迟，不能宣称严格即时性。显式kill能停worker，但需要远端接收控制动作，本任务不实现取消协议。
- **已入队`:ref`**：即使实际等待worker已经DOWN，Server的`$gen_call`仍存在；恢复后Server仍处理它，向已失效alias/死进程回复。`:ref`当前是只读处理，因此应区分“还处理一条只读消息”与“后台等待worker泄漏/启动有副作用操作”。
- **迟到响应**：活caller在**本地调用返回后等待1000ms**再单次采样，均未积累请求相关晚回复；这不是从远端完成或Server恢复起重新计满1秒。650ms远端预算场景通常只覆盖完成/恢复后约470ms，Endpoint超时场景在恢复后约1秒采样；无跨VM时钟相减或无限未来保证。alias/erpc弃结果解决的是响应污染，不是工作取消、过期准入或连接策略。

因此可讨论“允许有界只读后台完成”是否足够低扰动；也可保留现有Endpoint的新鲜准入/lease/noconnect等严格合同。这是取舍问题，不能用本地超时直接证明已满足严格合同。本文不替用户选择放宽契约。

## 保留的失败、验证与剩余缺口

- `20261017T120449-e632b0f5` smoke失败：原生peer未启动Elixir application就compile_file，`:elixir_config` ETS不存在。显式ensure_all_started(:elixir)后修复；不是无法启动工具/VM，也没有换CLI或代理绕过。
- `20261017T120659-0befdbb2` full失败：alias token是improper list，原JSON转换错误。增加保留head/tail的编码后修复；原日志曾保留，现依用户要求清理。
- `20261017T121120-9ff376ca` full失败：把send_safe返回硬写成noconnect的过强断言；当时未保存实际返回值，不反推具体值。
- `20261017T121228-62a496bb` full失败：保存了send_safe返回ok随后nodeup。最终不硬断言有利连接结果，另外增加双端rex交换完成屏障/本地trace。旧失败的确切发送者**未证明**，不可清洗成“已无条件证明原Endpoint从不重连”。
- `20261017T120750-ae706a2e` 是早期92场景成功，尚无最终全部补测；`121456-8ba95356` / `121852-7a0011f0` 均98场景成功；**最终以 `122252-5c3d06fc` 为准**，修正了Server恢复后再采样晚邮箱与elapsed字段，且无编译/弃用警告。
- 验证：显式脚本format check、warnings-as-errors compile、既有Discovery测试 **9 passed，seed631927**、JSONL语义审核、Python AST/compile、git diff检查全退出0。既有测试运行出现宿主memory/disk alarm通知，未把它们删去或解释为测试失败。
- 最终launcher对子进程组残留检查为空；每个peer记录control/os进程已退出，本地caller/helper真实不活，coordinator已连接节点为空；私有epmd停止。未触碰现有语言服务器VM或共享epmd。
- 产品路径无diff；没有stage、commit、换分支、修改task.json/规范/旧任务。整个任务目录原为untracked，因此不能仅以git diff --stat代表研究产物变更数量。
- **未执行/不宣称**：全仓测试/静态分析/LSP、第三方库安装或兼容实测、多物理机/生产性能、网络丢包/半开、超长负载、严格分布式即时取消、outer监督树restart-intensity升级、精确私有指令级public-query竞态冻结。
- 此实验seam仅提交实验和OTP事实，不宣称整个任务已经验收。恢复阶段已完成生态研究整合、最终 [report.md](report.md)、最小候选推荐及有证据的任务AC勾选；独立review现已完成，见 [quality-review.md](quality-review.md)：独立run `20261017T124152-6fd7b540` 同为98场景/98清理且通过，未发现连接分类差异。原实验raw/失败/源快照当时未覆盖，现已依用户要求清理。
