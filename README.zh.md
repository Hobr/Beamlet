# Beamlet

> 一个强大的 Agent

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
## Quint 模型检查
mix beamlet.check

## 低预算完整回归
mix beamlet.check --samples 20 --directed-samples 20

## 单独运行
mix beamlet.check --phase typecheck/test/simulate/mutations
```

模型覆盖、参数和日志说明见 [Quint 文档](model/quint/README.md)。

## 感谢

- [Erlang/OTP](https://www.erlang.org/)
- [Elixir](https://elixir-lang.org/)
- [Phoenix](https://www.phoenixframework.org/)
- [Elixir Desktop](https://github.com/elixir-desktop/desktop)
- [Mob Framework](https://github.com/GenericJam/mob)
- [Quint](https://github.com/quint-co/quint)
- [Nix](https://nixos.org/)
