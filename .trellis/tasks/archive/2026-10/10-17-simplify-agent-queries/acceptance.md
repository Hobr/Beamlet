# 简化 Agent 查询：验收报告

## 技术结论

**建议通过本次实现验收。AC1–AC6证据充分，无阻塞性产品缺陷；用户随后明确回复“接受”，AC7精确清理现已完成，见[清理记录](cleanup.md)。** 本报告是按用户“帮助我验收”完成的技术评估，不替代用户完成确认，不触发研究文件清理或提交。

## 验收时版本与证据适用性

留存更新：用户随后要求清理其余中间文件；验证日志、命令记录、启动脚本及哈希索引已删除。以下为验收时核查的历史摘要，产品回归仍保留在apps/。

- HEAD仍为9657d2a5b8b5288159e0663116cb0e6daed4913e，当前索引为空；本轮只读核查代码并写本报告，未stage/commit/push。
- 验收时对照实施者哈希索引，记录的全部生产代码、Node测试、fixture与spec哈希一致（该索引现已清理）。Agent discovery测试仅有主会话已补强并定向回归通过的读者PID断言。
- README与实施快照不同，目前已回到HEAD内容；不再声称当前README含新增查询说明。详细契约保留在backend/agent-orchestration.md第199行起，index/directory同步。没有因README恢复产生产品变化，不覆盖该外部改动。
- 旧研究results/和experiments/目录均存在。此前报告中的空索引、暂存区变化分别是不同观察时点，当前为空。
- 本轮未无条件重跑已通过检查：当前生产代码与验证候选一致，证据可复用。独立检查与实施者检查分开记录，不将旧研究98场景作为新产品测试。

## 验收矩阵

| 标准 | 实际行为与直接证据 | 判定 |
| --- | --- | --- |
| AC1 简化且无新依赖 | Discovery固定local/erpc入口；Endpoint源码及两处注册删除；传输288→153行、2→1模块；依赖manifest/lock无变更 | 通过 |
| AC2 查询失败不伤Agent | discovery_test.exs:71/96/111与discovery_distributed_test.exs:94/114/130/150：暂停真实Server、识别实际reader、超时/kill/caller死亡/断线后在Server恢复前确认reader退出，恢复后原Ref及idle/turn状态保留；独立lifecycle15项含真实Registry失效 | 通过 |
| AC3 身份和部分结果 | discovery_test.exs:21及discovery_distributed_test.exs:52：真实list/lookup、同名authority、ID复用、旧descriptor拒绝、关闭/重启、not_authority；agents_test.exs保留错误信封 | 通过 |
| AC4 时限/并发/上限/保密 | query_local只收1..5000相对预算；本地截止先分配；十peer实际观测8个在途请求、10个timeout及共享约5s预算；32节点/128身份/完整1MiB信封与SECRET标记排除断言；caller晚回复检查 | 通过 |
| AC5 装配及长期回归 | 七角色能力断言；CLI重新附着及daemon宿主回归；产品测试独立于旧研究；backend规范明确OTP取消/重连边界 | 通过 |
| AC6 不提交及延迟清理 | HEAD未变；本会话未暂存/提交/推送；旧目录保留，AC7未勾选 | 通过 |
| AC7 精确清理与引用修复 | 用户在技术验收后明确回复“接受”；按限定清单删除旧实验并修复引用，产品代码不变 | 已完成 |

以上证据位置均相对仓库根的apps/beamlet_agent/test/beamlet/agent/、apps/beamlet_node/test/beamlet/。完整调用/错误/边界规范见.trellis/spec/backend/agent-orchestration.md。

## 验证证据的强弱

- 实施者最终常规194通过/25 excluded；命名宿主101通过；最终命名发现9通过含resource。分别是不同执行，不相加冒充独立用例总数。
- 独立检查PASS，实际命名发现/resource9通过、普通聚焦42通过/3 excluded及生命周期15通过；编译、格式、strict Credo均退出0。
- 独立命名执行缺shell退出码，但有完整9 passed ExUnit摘要及进程清理证据；实施者最终命名执行有退出0记录。因此不是完全缺失命名成功证据。
- 后续唯一测试断言加强的定向回归：1 passed/6 excluded，退出0，seed648055；原日志已依用户要求清理，此处留存结果摘要。
- dev Dialyzer零错误；test Dialyzer因web测试支持的ExUnit PLT缺函数失败，不算通过。主动LSP四文件超时，结果不确定。二者不否定已有编译/实际行为证据，但不声称所有分析全绿。

## 用户需要了解的最终行为

1. 查询失败不会通过已删除的Endpoint监督耦合终止Agent；Registry/authority自身故障仍可使旧身份失效，这是保留的业务边界。
2. 调用者超时或退出代表放弃响应。远端只读查询可能稍后开始，并在自身最多5s读取预算内结束；不承诺立即取消或删除已入Agent邮箱的ref消息。
3. 入口拒绝已断开的目标；预检查后断线，OTP可以重连。没有业务重试或自动重建Agent。
4. 结果是观察时点身份，后续仍可失效；不提供持久恢复或混版本兼容回退。此次验证限同机真实peer，不扩展为跨物理机/半开网络/长期压力保证。

这些边界与用户已批准的R4一致，不是本轮新增的验收条件。技术验收后用户已明确接受；随后完成限定的旧研究清理，仍不提交。

## 来源

- [实现验证](verification.md)
- [独立检查](independent-review.md)
- [需求与AC](prd.md)
