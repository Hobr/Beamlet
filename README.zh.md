# Beamlet

**WIP**, 在首个 Release 前可能存在破坏性更改

## 包

以下为规划中的包边界。

### Engine

- Beamlet：核心 Effect 系统
- Beamlet-Runtime：Effect 执行运行时

### Beamlet!!!!!

- Beamlet-Agent：基于 Effect 系统的 AI Agent 循环
- Beamlet-CLI: 命令行界面
- Beamlet-TUI: 交互式终端界面
- Beamlet-Web: 基于 Phoenix LiveView 的 Web 工作台
- Beamlet-Mobile: 移动端界面

## 构建

```bash
# 开发环境
nix develop

# 包管理
## 安装 Hex
mix local.hex

## 获取依赖
mix deps.get

## 更新依赖
mix deps.update --all

# 编译
mix compile

# 生产环境编译
MIX_ENV=prod mix compile

# 网站服务器
mix phx.server

# 格式化
pre-commit run --all-files

# 测试
mix test

# Quint
mix quint {all/typecheck/test/simulate/mutations}
```

## 感谢

- [Erlang/OTP](https://www.erlang.org/)
- [Elixir](https://elixir-lang.org/)
- [Phoenix](https://www.phoenixframework.org/)
- [Elixir Desktop](https://github.com/elixir-desktop/desktop)
- [Mob Framework](https://github.com/GenericJam/mob)
- [Quint](https://github.com/quint-co/quint)
- [Nix](https://nixos.org/)
