# Beamlet

**WIP**, with broken changes before the first release.

## Usage

### Nix

```bash
# List
nix flake show github:Everfold/Beamlet

# Node
nix run github:Everfold/Beamlet#beamlet-node -- --version
nix run github:Everfold/Beamlet#beamlet-console -- --version
```

## Build

### Development Environment

#### Linux

```bash
apt install rustup \
  cargo-binstall \
  just
```

#### Nix

```bash
# Nix Shell
nix develop

# OR Direnv
apt install -y direnv
echo 'use flake' > .envrc
direnv allow
```

#### Quint (Optional)

```bash
npm i @informalsystems/quint -g
```

### Project

```bash
# Dev Tools
just install-dev

# Run
just console
just node

# Build
just build

# Release Build
just release

# Check
just check

# Format
prek install
just fmt

# Test
just test

# Doc
just doc

# Generate licenses.html
just license

# Update
just update
```
