# Beamlet

> Durable computation runtime where effects are persisted, resolved to capabilities, and executed across a BEAM cluster. && Agent runtime built on composable capabilities and durable effects.

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
mix quint.quick     # Type checking and determinism tests
mix quint.simulate  # quick plus 10,000 combined sampling traces
mix quint.verify    # quick plus bounded check with depth 10
mix quint.verify --timeout 900  # Optional: limit each backend check to 900 seconds
mix quint           # Runs quick, simulate, and verify
mix quint all       # You can also explicitly select all
mix quint --cores 16 --timeout 0  # Full core suite, no BMC time limit
```

## Concept

- Beamlet-lib: Engine.
- Cordex: OTP-native implementation of Cordis for spatiotemporal composability.
- Beamlet-agent: Agent based on Beamlet-lib.
- Beamlet-{cli, tui, web, desktop, android, node}: A set of frontends for Beamlet-agent.

These dependencies will be sperated into separate projects in the future.

## Thanks

- [Erlang/OTP](https://www.erlang.org/)
- [Elixir](https://elixir-lang.org/)
- [Phoenix](https://www.phoenixframework.org/)
- [Elixir Desktop](https://github.com/elixir-desktop/desktop)
- [Mob Framework](https://github.com/GenericJam/mob)
- [Quint](https://github.com/quint-co/quint)
- [Nix](https://nixos.org/)
