# Beamlet

> A Powerful Agent.

**WIP**, with broken changes before the first release.

## Build

```bash
# Development shell
nix develop

# Package
mix local.hex
mix deps.get
mix deps.update --all

# Format
mix format

# Compile
mix compile

# Test
mix test

# Quint
## Quint model checks
mix beamlet.check

## Low-budget full regression
mix beamlet.check --samples 20 --directed-samples 20

## Single phase
mix beamlet.check --phase typecheck/test/simulate/mutations
```

See the [Quint documentation](model/quint/README.md) for model coverage, parameters, and logs.

## Thanks

- [Erlang/OTP](https://www.erlang.org/)
- [Elixir](https://elixir-lang.org/)
- [Phoenix](https://www.phoenixframework.org/)
- [Elixir Desktop](https://github.com/elixir-desktop/desktop)
- [Mob Framework](https://github.com/GenericJam/mob)
- [Quint](https://github.com/quint-lang/quint)
- [Nix](https://nixos.org/)
