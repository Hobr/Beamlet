# Beamlet

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

# Format
pre-commit run --all-files

# Test
mix test

# Dialyzer
mix dialyzer

# Static analysis
mix credo

# Phoenix security static analysis
mix sobelow

# Example benchmark
mix bench

# Generate SBoM
mix sbom.cyclonedx
```

## Thanks

- [Erlang/OTP](https://www.erlang.org/)
- [Elixir](https://elixir-lang.org/)
- [Phoenix](https://www.phoenixframework.org/)
- [Elixir Desktop](https://github.com/elixir-desktop/desktop)
- [Mob Framework](https://github.com/GenericJam/mob)
- [Nix](https://nixos.org/)
