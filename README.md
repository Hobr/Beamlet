# Beamlet

**WIP**, with broken changes before the first release.

## Build

### Development Environment

#### Linux

```bash
apt install rustup \
    cargo-binstall \
    pre-commit \
    just \
    libwebkit2gtk-4.1-dev \
    build-essential \
    curl \
    wget \
    file \
    libxdo-dev \
    libssl-dev \
    libayatana-appindicator3-dev \
    librsvg2-dev \
    lld
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

# Run
just console
just node
just web
just desktop

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

# Doc
just doc

# Generate licenses.html
just license

# Update
just update
```
