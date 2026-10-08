# 核心验证与协议设计评审报告

[ADR-008 协议补充及关联细化](../../architecture/protocol-review-2026-10-08.md)经过独立技术评审、串行修订、最终独立检查和父会话设计验收后接受。ADR-007 中 Ra 仍是条件候选；architecture-v1 与 ADR-001–006 历史理由保持。**完整组合 depth10 仍无结论，实际 I1–I4 运行时验证未执行。** 技术处置、已执行模型证据和实现采用分开记录。

所有验证证据都只保留在本地、受 Git 忽略，包括 `spec/quint/core/evidence/retained/`。它们用于审计、核对来源身份与复现诊断，不是提交清单。新检出可以读取本报告的准确摘要、[模型与运行命令](README.md)及[设计评审记录](../../architecture/protocol-review-2026-10-08.md)，但无法独立检查未提交的原日志。本轮中文文档与忽略策略更新没有新增模型、测试、抽样、编译或后端执行结果。

<a id="final-independent-pending-design-check"></a>

## 当前结果与独立检查

最终 pending-design checker 独立读取主契约、原始只读发现、模型和实际日志，确认 P1/P2 与捕获模式对应修订已落实，无已知剩余范围内设计阻塞；父会话单独接受该门禁。最终检查重新执行 core_test typecheck 与46测试，复用其余依赖未变的模型证据。

工具为 Quint0.32.0、随附 Apalache0.56.1/build70cdaf4、Java21.0.12.1+1。组合域为 Runs0/1、每 Run 一个 Effect、Attempts0/1、owners0/1、FIFO6，默认 init/step/safety 保留全部核心、故障、控制与源/分支动作。恢复域为 Run0/FIFO4，使用明确受限的14转换调度。

| 检查与归属 | 实际配置与结果 | 界限 |
| --- | --- | --- |
| 修复独立 checker 的六项 typecheck | model、small、composition、core_test、recovery、recovery_test，全部 exit0 | core_test 当时为43测试；后续测试文件变化有独立身份 |
| pending-design 最终独立 typecheck | `quint typecheck spec/quint/core/core_test.qnt`，exit0 | 检查当前测试文件 |
| pending-design 最终独立测试 | TypeScript/main core_test/`--match '.*Test'`/seed20261014；46通过，28正例/18检测变异，exit0 | 只建立显式路径与变异断言 |
| 修复独立恢复测试 | main recovery_test；14实际转换，逐步 safety/premises/严格递减 rank，最终 consumed/finished；exit0 | 固定调度路径 |
| 修复独立代表组合 | combinedTest；25状态/24转换，含源/分支工作、恢复与迟到观测；exit0 | 可达性，不是开放组合进度证明 |
| 修复独立非空检查 | 实际默认 init 执行 safety，十个目标初始均 false；exit0 | witness 不依赖初始化即成立 |
| 修复独立代表抽样 | Rust/main composition/默认 init+step/safety；10,000条、depth60、seed 参数20261014；exit0，无采样反例；78.280秒求值/85.006秒管理耗时，复现 seed0x35e178f | 非穷举，消费稀疏 |
| 修复独立完整组合 BMC | depth10/所有动作/init+step/safety/random-transitions=false；240秒/port8863；240.054秒在 State5 超时，exit124 | 无完成请求界限，也无任何较小界限 |
| 修复独立受限恢复 BMC | recovery.init/step/safety（含 core safety、premises、rankDecreases）；depth14/random-transitions=false；120秒/port8864；exit0/NoError，82.029秒求值/90.008秒管理耗时 | 仅指定恢复调度 |

管理执行时间为 `2026-10-08T08:22:38.421285+08:00` 至 `2026-10-08T08:29:33.505607+08:00`。最终文档归属与包装文件身份不改变这个执行时间，也不表示新运行。

| 非初始 witness | 10,000条中的确切计数 |
| --- | ---: |
| intentWitness | 1791 |
| entryWitness | 139 |
| unknownWitness | 225 |
| recoveryWitness | 158 |
| consumedWitness | 5 |
| recoveryConsumedWitness | 1 |
| branchWorkWitness | 567 |
| inconclusiveWitness | 16 |
| failedUnknownWitness | 10 |
| failedReplyWitness | 5 |

十项均正，但消费5与恢复消费1仍稀疏。计数相同不证明新竞态得到覆盖；新竞态的直接依据是独立回归与检测变异。恢复调度要求可用权威、active 控制、兼容且活着并成功的替代主体、显式 repeat、合法步骤/finish、容量、指定动作最终得到调度，且无额外干扰。它不建立任意状态恢复、一般活性或开放组合安全。

<a id="source-decisions-and-model-corrections"></a>

## 协议评审发现与处置

只读 reviewer 的 P1 指出：较早 not_executed 已解除某 Attempt 后，迟到且具有不同 observation_id 的监视器失联报告，可能按旧 unknown 行重新打开不确定性并追加通知。这是源契约闭合缺口，不是已执行运行时故障。经[父会话明确决定](../../../.trellis/tasks/10-07-quint-architecture-verification/research/pending-monitor-supervisor.md)，迟到报告仅保留有来源审计，不覆盖同一 Attempt 的确定观测、Effect/结果或重新通知；局部失败仍可逻辑未决，另一新 Attempt 的失联独立处理。

模型 `lose` 本来只接受 Admitted，因此动作、归约、属性、init/step 与域未变。新增三个测试分别检查有效非执行事实与 lose 拒绝、局部失败未决且 lose 拒绝，以及另一 admitted Attempt 变为 unknown。**它们不投递排队的 distinct-ID monitor 载荷，不持久化该载荷审计。** 实际处理器行为仍归属 I2/I3/S4。writer 执行这三个 focused 测试与全部46测试，随后最终 checker 独立重新检查全部46测试。测试书写时出现的 QNT502 是开发诊断；把断言移到 fail() 前后通过，未改变模型。

P2 固定 Ra API 为 v3.2.0，并要求采用配置拒绝 `wal_sync_method=none`。OperationDeclaration、Effect 意图与捕获表补齐既有声明引用/版本/失败含义，与既有失败契约对应。独立 source auditor 未发现被审查版本化主张的实质矛盾；最终 checker 重新检查 Ra3.2.0 / OTP-29.0 API、WAL、配置、支持列表与 codec/heap 段落。源码只支持候选性与边界，不是成功构建、端到端持久 quorum 或资源测试。

最终 checker 核对七项复用可执行依赖及 writer 的22项来源/测试身份。父会话在归属文字更新前独立核对，再单独保存更新后的文档身份。完整逐项理由、替代取舍和未执行义务见[协议评审记录](../../architecture/protocol-review-2026-10-08.md#parent-acceptance)。Mnesia / disk_log 比较仅解释既有替代方案，本轮没有新增依赖、后端、运行时实现或采用选择；Ra 仍是唯一条件候选。

<a id="preserved-independent-repair-gate-report"></a>

## 修复独立门禁的历史归属

修复门禁当时 ADR-008 仍 proposed，没有执行后来的设计评审。独立 checker 修复三项缺陷：失败归约漏掉其他 admitted 工作；恢复表排除了原实例重复分发下的首次合法进入；执行器只验证十个请求 witness 中的七项。修复后的43测试含25正例/18变异，六项 typecheck、恢复路径、代表组合、抽样及上述 BMC 结果归属该阶段。后续设计评审增加三个测试，当前总数为46。

失败声明在求值时捕获并固定，普通错误、超时或注册表变化不能赋予逻辑失败含义。`unresolved` 根据授权与真实保留观测判断，不能从 `Recorded` 推断解决。正常结果选择集中归约；`terminalChoice`、`normalReductionRequired` 与 C3 从独立前态授权、物理观测和证据检查，不调用 reducer 或 guard 作证明。

回归覆盖未进入的替代授权、本地完成但未记录、有效成功、非执行使保留失败充分、局部失败仍未决，以及漏掉 admitted blocker 的检测变异。结果记录前保持 NoResult/Executing，有效成功记录后只产生一个 Ok/Reply。原实例未进入时可以至多首次调用一次；已进入的重复分发只查状态/重报。执行器共享一个 witness 数组，并拒绝20个 missing/zero 注入案例；实际十项正计数日志通过。

failed 保持封闭：无 resume、新 admit、commit、repeat 或 settle；原授权和迟到观测保留，未决信息可审计；晚回复为 Unprocessed，不能重新把 Effect 标为 Consumed。稳定前缀是只读值，新分支采用新队列、身份和权限。没有增加取消、终态人工 settlement 或证据自动删除。

## 两个必须保留的原始缺陷

| 历史来源 | 原始缺陷与证据 | 当前处置 |
| --- | --- | --- |
| 原模型 SHA256 `1f90f89830e3a9ae1be741ee3f836563bafb855d6819da97389ee34602f4da99` | 旧 Attempt unknown、恢复 Attempt 逻辑失败、旧 Attempt 后证明未执行；旧模型却保持 NoResult/Dormant/无 Reply。要求 Error/Reply 的 regression exit1；单独坏行为 probe exit0 | 保留全部有效观测归约；passing bad-behavior diagnostic 不计入修复验收 |
| writer 模型 SHA256 `7e076a320a8d8d52b9050bf7c20155a0939b2ed809c568505fd49741f5e676cb` | Attempt0 unknown、repeat 授权 Attempt1、Attempt0 失败记录时 Attempt1 仍 admitted；旧模型在状态10选 Error，状态13成功观测后仍 Error。要求 NoResult/Executing 的 assertion exit1；14状态/13转换 diagnostic exit0 | 其他已授权且无权威确定观测的工作阻止失败，包括未进入/执行中/本地已完成未记录；有效成功仍充分 |

原始 model 与相匹配的 probe/test 相邻保留，本地路径分别为 `spec/quint/core/evidence/retained/defects/retained-logical-failure/` 与 `spec/quint/core/evidence/retained/defects/admitted-work/`，均 Git 忽略。必需失败日志、源哈希和选定 ITF 只用于本地审计；新检出不包含它们。历史 diagnostic 通过只说明坏行为可达，不能称为已修复。

<a id="current-source-executed-evidence"></a>
<a id="identity-and-remaining-obligations"></a>

## 来源身份、复现与剩余义务

| 可复用依赖 | SHA256 |
| --- | --- |
| model.qnt | `7d98f1ff5ff4d31a2deb3d365d1b6bb6f4d5e3011d5af571e82eb5ade4044482` |
| composition.qnt | `ab9317006bd7465712c9aa04a802aaf8fa460aae31f66346087c7fc98f9fd73d` |
| recovery.qnt | `bb0101a96b58d926145b5324e1dac8869a610e9e73a9b2166b8c6af8957e0096` |
| recovery_test.qnt | `e81a122f87d54c8f6b0d0e78d7c9bbab727ccde561a0065466c9c6533d8a9ea3` |
| small.qnt | `676f33f1ab16341aa1c2df16858cb15a330296e87304203440671b68c946f13d` |
| check.sh | `4c5204a186fd319c4159bd95996fa5df124d8e43c8c10739a4679f50f65503dd` |
| verify.py | `3b2067c0fa1cb3610d739678213d39b9646520df4fbe3e0dd59c09e36f5fe740` |

当前 core_test SHA256 为 `af91532b7835a31727f0e5635a6aeff2e1411bab9cd889a77446ac18c1907986`；先前43测试文件身份为 `2fb110a082f743fb436d777d77d6a15d16386209b2f88f5d8c31c5d9e67ab39e`。测试变化没有改组合依赖。入口哈希不变不能让已变模型复用旧证据；早期900秒尝试与中间修复仍按原 model 哈希限定。

以下是新检出可运行的复现命令，**本轮未执行**。复现会生成新证据，不能把它与历史运行混为一谈。

```sh
quint typecheck spec/quint/core/core_test.qnt
quint test spec/quint/core/core_test.qnt --main core_test --match '.*Test' --backend typescript --seed 20261014
quint test spec/quint/core/recovery_test.qnt --main recovery_test --backend typescript --seed 20261014
quint test spec/quint/core/core_test.qnt --main core_test --match combinedTest --backend typescript --seed 20261014 --out-itf '/tmp/combined_{test}_{seq}.itf.json'
quint run spec/quint/core/composition.qnt --main composition --invariant safety --witnesses intentWitness entryWitness unknownWitness recoveryWitness consumedWitness recoveryConsumedWitness branchWorkWitness inconclusiveWitness failedUnknownWitness failedReplyWitness --max-samples 10000 --max-steps 60 --seed 20261014 --verbosity 1
python3 spec/quint/core/verify.py 240 8863
python3 spec/quint/core/verify.py 120 8864 spec/quint/core/recovery.qnt recovery 14
```

实际原始命令、版本、域、init/step/property、时间、退出与来源哈希保留在本地 Git 忽略的 `spec/quint/core/evidence/design-repair/independent-review/`、`pending-design-review/`、`pending-design-final-check/` 及 `retained/` 中。`retained/manifest.json` 记录逐字副本来源；旧路径属于本地来源归属，不是新检出依赖。早期完整组合 depth10/240秒/port8852 State5 与900秒/port8854 State6 超时，仅绑定原模型 `1f90f898…`；900秒耗时900.133秒。没有任何完成界限。大型探索套件的 serializer/未完成界限和缺口仍见[历史报告](../verification-report.md)，不由核心门禁清零。

I1–I4 仍须实际 Ra/磁盘/quorum、命令/授权/回执、进程/提供者/版本/资源和 codec/archive 故障测试。核心只保留观测分类与单次物理完成，完整载荷/来源历史与兼容性是前提。有限 ID/FIFO、稀疏消费、条件调度限制结论；没有一般活性证明。无运行时、包、工具链、依赖或后端扩展。证据全部本地的最新用户要求已取代此前可提交 compact pack 的提议；提交清单排除整个 evidence 目录。
