# Beamlet

**WIP**, with broken changes before the first release.

## Build

### Development Environment

#### Linux

```bash
sudo add-apt-repository ppa:longsleep/golang-backports
sudo apt update
sudo apt install golang-go \
  golangci-lint

# Go Task
go install github.com/go-task/task/v3/cmd/task@latest

# [Prek](https://prek.j178.dev/installation/) (Optional for git commit hooks)
pnpm add -g @j178/prek
```

If don't want to install go-task:

```bash
# Gopls
go install golang.org/x/tools/gopls@latest

# Go Vulncheck
go install golang.org/x/vuln/cmd/govulncheck@latest

# Panicparse
go install github.com/maruel/panicparse/v2/cmd/pp@latest

# Delve
go install github.com/go-delve/delve/cmd/dlv@latest

# Go Licenses
go install github.com/google/go-licenses/v2@latest

# Gup
go install github.com/nao1215/gup@latest
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
# Install dev tools
task install-dev

# Format
task fmt

# Check (Lint + test)
task check

# Vulnerabilities
task vuln

# Build
task build

# Update (Deps + Tools)
task update
```
