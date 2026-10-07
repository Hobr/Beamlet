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
```

## Concept

- Beamlet-lib: Engine.
  - Beamlet-core: Core runtime for Beamlet-lib.
  - Beamlet-effect: Effect system for Beamlet-lib.
  - Beamlet-durable: Durable effects for Beamlet-lib.

- Cordex: OTP-native implementation of Cordis for spatiotemporal composability.

- Beamlet-agent: Agent based on Beamlet-lib.
- Beamlet-{cli, tui, web, desktop, android, node}: A set of frontends for Beamlet-agent.

These dependencies will be sperated into separate projects in the future.

## Specifications

The [specification library](./spec/README.md) documents the target runtime contracts, module boundaries, recovery semantics and architecture decisions. Start with the [architecture index](./spec/architecture/index.md).

## Thanks

- [Erlang/OTP](https://www.erlang.org/)
- [Elixir](https://elixir-lang.org/)

- [Phoenix](https://www.phoenixframework.org/)
- [Elixir Desktop](https://github.com/elixir-desktop/desktop)
- [Mob Framework](https://github.com/GenericJam/mob)

- [Quint](https://github.com/quint-co/quint)
- [Nix](https://nixos.org/)
