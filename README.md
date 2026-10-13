# Beamlet

> A Powerful Agent.

**WIP**, with broken changes before the first release.

## Build

```bash
# Development shell
nix develop

# Package
## Install Hex
mix local.hex

## Fetch dependencies
mix deps.get

## Update dependencies
mix deps.update --all

# Compile
mix compile

# Production build
MIX_ENV=prod mix compile

# Format
pre-commit run --all-files

# Test
mix test

# Quint
mix quint {all/typecheck/test/simulate/mutations}
```

## Thanks

- [Erlang/OTP](https://www.erlang.org/)
- [Elixir](https://elixir-lang.org/)
- [Phoenix](https://www.phoenixframework.org/)
- [Elixir Desktop](https://github.com/elixir-desktop/desktop)
- [Mob Framework](https://github.com/GenericJam/mob)
- [Quint](https://github.com/quint-co/quint)
- [Nix](https://nixos.org/)
