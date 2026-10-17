# Host and Preset Design

## Authority

遵循[父设计 §2/§3/§5](../10-17-beamlet-web/design.md)；source anchors 见父 research/current-capabilities.md。新增文件留在 Beamlet.Web.* 命名空间。

## Supervision/config

Web child manifest 直接依赖实际调用的共享库，不依赖 daemon/CLI。Host disabled-by-default；enabled 显式装配一个包含 interaction 的 Node 角色组合及 owned one-shot peer bootstrap，普通 endpoint 不因缺业务配置假造 Agent。重用 Node.configuration/Cluster，不复制名称校验；无远程输入触发 Node.connect。

受信 startup catalogues 最多32 presets/32 models/64 tools/32 environments。仅允许有界数据定义和受信已安装适配器；模型凭据保留 server-only。工具根/settings 在 executor-local。public descriptor 与 private resolver 分开，错误只返回安全字段/静态原因，决不 inspect raw config。

## Resolution and commands

Preset defaults + draft 公共 ID 选择 → allowlisted lookup → 检查环境/工具相容性 → 构造匹配 tools/catalogue 和不可变 model binding → Agent.start → Agent.input。每步有明确成功/失败/未知结果，Agent.start 远程静态错误无法证明未创建时按不确定处理，不制造更强保证。

Agent 名称/preset 来源由前置子任务的安全 display_metadata 保存为实例内临时字段；不是模型配置，也不是持久化。创建时条件校验不得调用 provider 或工具。提供显式 deterministic 开发示例，不自动读取真实模型 key。

Handles 是随机 opaque id 到当前 descriptor/Ref 的 VM-local bounded map（4096 entries、1小时 idle expiry）；映射不存 transcript/凭据。参数只能引用已存在句柄，不能解码任意 PID、atom、external term。重启清空；过期后重新发现，旧句柄不转指其他实例。

## Compatibility/rollback

Host 关闭后现有 endpoint/测试可工作；backend 构建不带入 Phoenix，核心保持无 Web 依赖。修改 host startup config 是下次启动生效，不是 hot reload。回滚关闭 opt-in host 并恢复配套配置，不声称业务 undo。
