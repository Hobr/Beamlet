# Beamlet

**WIP**, with broken changes before the first release.

## Build

### Nix

```bash
# Nix Shell
nix develop

# OR direnv
apt install -y direnv
echo 'use flake' > .envrc
direnv allow
```

### AI (Optional)

```bash
npm install -g @mindfoldhq/trellis@latest @colbymchenry/codegraph
trellis init -u <your-name>
codegraph install
codegraph init
```

### Project

```bash
go tool task
```
