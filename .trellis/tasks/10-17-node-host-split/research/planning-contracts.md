# 已确认的产品决策与共享实施约束

## User decisions

- 复用用户已创建并提交的 daemon/CLI OTP 骨架；Node 是库，宿主负责启动/部署。
- CLI 是单进程会话式 interaction 客户端，但不能把会话内别名作为 Agent 唯一访问途径；需要发现并附着集群中已有的存活 Agent。
- 保留 Node 可嵌入/三角色组合和 Agent/Runtime 业务接口；旧 Node.CLI、Node Application、:boot 和 Node release 直接淘汰，不加兼容转发。
- Daemon 不提供 interaction；一个 daemon 发布产物包含 authority/executor 能力，程序启动时选择两者或单一 only，默认双角色；不实现运行期切换。
- 发布方案仅 mix release，未来 Web 直接集成 Node 的三角色组合；本次不开发 Web/TUI/Desktop。

## Normative documents

父 PRD 是需求源，父 design.md 定义共享技术契约，父 implement.md 定义完整验证门禁。子任务实现前需连同自身三份文档读取；本记录用于跨子任务注入。用户已在最终规划摘要之后明确回复“确认”，实施门禁已满足；主会话按 node-library → daemon-host → agent-discovery → cli-host 顺序逐一启动子任务，父任务保留协调身份。每个子任务仍需 status=in_progress 才可写产品代码。

现有 backend spec 是 baseline，部分“Node 自启动/CLI/release”和“无公开 lookup”描述将由本次需求替换；不能拿旧实现缺口拒绝新需求。其他凭据、绑定、Runtime、Gateway、订阅及不确定性约束仍适用。

## Key contracts

- Node 仍是可监督库，支持全部七种非空角色组合；daemon/CLI Application 默认空启动，release runtime 配置显式启用目标宿主。固定注册名设计保持，每 VM 一套 Node。
- Node.Cluster 负责可信名称/连接；Agent 库负责 authority-local list/lookup；Node.Agents 聚合已连接可信目标。Agent 不依赖 Node，宿主之间无依赖。
- list 投影 authority/id/pid，lookup 向真实 Server 取得 Ref，不使用 :sys.get_state、不拼造 Ref、不返回模型 binding/凭据。descriptor 附着校验 expected PID，显式 authority+ID 查询选择当下实例；旧 Ref 不静默重绑。
- 聚合最多32节点/8并发、总接收预算5秒、完整结果1MiB上限。未找到/非authority/不可达/超时与部分结果可区分，complete 仅针对请求节点集合，绝不假装全局强一致视图。
- CLI 使用有界别名表、显式 authority 命令与可信绝对 creation-options 配置；不提供通用 eval，不回显秘密。watch 复用原 credit/60秒/256事件/4096 codepoints 边界；quit/EOF/detach 不关闭 Agent，显式 close 才请求关闭。
- 同一 daemon copy 三种启动配置 + CLI interaction copy 的实际 named start/RPC/stop/stdin 检查；后端无 Web secret，控制 helper 临时端口避免服务端口碰撞。
- 不提供持久化恢复/迁移/历史重放/业务自动重试/全局永久唯一ID/多租户授权。客户端重新附着存活实例与恢复已消失实例是两件事。

## Delivery order and risks

node-library → daemon-host → agent-discovery → cli-host；父任务只做集成与验收。先迁移原 CLI 终端适配器/测试，再开发完整会话，避免阶段性断掉普通测试或留下双份逻辑。关注宿主加载冲突、Helper 实际退出、partial误读、ID复用、stdin阻塞、敏感日志和release闭包。没有授权物理远程部署或付费 provider 调用。
