set positional-arguments

console_package := "beamlet-console"
node_package := "beamlet-node"
default:
    @just --list

install-dev:
    cargo binstall prek cargo-deny cargo-nextest cargo-update cargo-about diesel_cli flutter_rust_bridge_codegen -y --force
    cargo deny fetch

console *args:
    cargo run --package "{{console_package}}" -- "$@"

node *args:
    cargo run --package "{{node_package}}" -- "$@"

build: build-console build-node

build-console *args:
    cargo build --package "{{console_package}}" "$@"

build-node *args:
    cargo build --package "{{node_package}}" "$@"


release: release-console release-node

release-console *args:
    cargo build --release --package "{{console_package}}" "$@"

release-node *args:
    cargo build --release --package "{{node_package}}" "$@"

check:
    cargo check --workspace

fmt:
    cargo fmt --all
    prek run --all-files

test:
    cargo nextest run --workspace --all-features

doc:
    cargo doc --workspace --no-deps

license:
    cargo about generate --workspace about.hbs > licenses.html

update:
    cargo install-update -a
    cargo update
    cargo deny fetch
    prek autoupdate
    nix flake update
    npx skills update
