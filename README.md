# Beamlet

**WIP**, with broken changes before the first release.

## Workspace Layout

- crate/
  - kernel: Durable operation and execution protocols
  - store-sqlite: SQLite persistence adapter
  - transport-zenoh: Zenoh transport adapter

  - harness: Composable agent capabilities
  - llm: Language model execution adapters
  - tools: Tool execution adapters

- apps/
  - cli: Command-line application for Beamlet Agent Harness

## Build

### Development Environment

#### Linux

```bash
apt install -y rustup cargo-binstall protobuf-compiler pre-commit just
```

#### Nix

```bash
# 1. Nix Shell
nix develop

# 2. Direnv
apt install -y direnv
echo 'use flake' > .envrc
direnv allow
```

#### AI (Optional)

```bash
npm install -g @mindfoldhq/trellis@latest @colbymchenry/codegraph
trellis init -u <your-name>
codegraph install
codegraph init
```

### Project

```bash
# Dev Tools
just install-dev

# Build
just build

# Release Build
just release

# Check
just check

# Format
just fmt

# Test
just test

# Coverage
just coverage

# Doc
just doc

# Update
just update
```
