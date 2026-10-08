# Beamlet

> 持久化计算运行时: 保存 Effect, 转为 Capabilitie，跨 BEAM 集群执行
> 基于可组合能力与持久 Effect 构建的 Agent 运行时

**WIP**, 在首个 Release 前可能存在破坏性更改

## 构建

```bash
# 开发环境
nix develop

# 包管理
mix local.hex
mix deps.get
mix deps.update --all

# 格式化
mix format

# 编译
mix compile

# 测试
mix test

# Quint
mix quint.quick     # 类型检查与确定性测试
mix quint.simulate  # quick 加 10,000 条组合抽样轨迹
mix quint.verify    # quick 加深度 10 的有界检查（默认预算 240 秒）
CORE_VERIFY_TIMEOUT=900 mix quint.verify  # 可选：将后端预算设为 900 秒
mix quint           # quick、simulate、verify 全部执行
mix quint all       # 也可显式选择 all
```

## 概念

- Beamlet-lib: 引擎
- Cordex: 面向时空可组合性的 Cordis 的 OTP 原生实现
- Beamlet-agent: 基于 Beamlet-lib 的 Agent
- Beamlet-{cli, tui, web, desktop, android, node}: Beamlet-agent 的前端程序

这些依赖项将来会被拆分为独立的项目

## 感谢

- [Erlang/OTP](https://www.erlang.org/)
- [Elixir](https://elixir-lang.org/)
- [Phoenix](https://www.phoenixframework.org/)
- [Elixir Desktop](https://github.com/elixir-desktop/desktop)
- [Mob Framework](https://github.com/GenericJam/mob)
- [Quint](https://github.com/quint-co/quint)
- [Nix](https://nixos.org/)
