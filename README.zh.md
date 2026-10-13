# Beamlet

> 一个强大的 Agent

**WIP**, 在首个 Release 前可能存在破坏性更改

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
