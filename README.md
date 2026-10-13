# Beamlet

**WIP**, with broken changes before the first release.

## Packages

The planned package boundaries are:

### Engine

- Beamlet: the core Effect system
- Beamlet-Runtime: the runtime for running effects

### Beamlet!!!!!

- Beamlet-Agent: an AI agent loop built on the Effect system
- Beamlet-CLI: a command-line interface
- Beamlet-TUI: an interactive terminal interface
- Beamlet-Web: a web workbench built with Phoenix LiveView
- Beamlet-Mobile: a mobile interface

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

# Web server
mix phx.server

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
