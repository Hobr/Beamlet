# Beamlet

**WIP**, with broken changes before the first release.

Backend release, CLI/IEx, trusted multi-host configuration and acceptance:
[deployment runbook](scripts/deployment/README.md). Local automated evidence is
based on independent VMs and copied-release checks. Physical-host execution is
untested; its acceptance requirement was removed for this MVP.

Models use trusted local `model_providers` registrations and one immutable
Agent-owned provider/config/credentials/placement binding. Supply credentials at
Agent creation; executor Tool profiles and workspace settings remain local.
Legacy model profiles and `key_env` are rejected without environment fallback.
Deploy matching builds. Credentials may remain in plaintext process/message copies
until ordinary cleanup; secure memory erasure is not promised. See the runbook for
creation, child isolation and deployment examples.

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
