set positional-arguments

console_package := "beamlet-console"
node_package := "beamlet-node"
web_package := "beamlet-web"
desktop_package := "beamlet-desktop"
mobile_package := "beamlet-mobile"

default:
    @just --list

install-dev:
    cargo binstall prek cargo-deny cargo-nextest cargo-update cargo-about dioxus-cli -y --force
    cargo deny fetch

console *args:
    cargo run --package "{{console_package}}" -- "$@"

node *args:
    cargo run --package "{{node_package}}" -- "$@"

web *args:
    dx serve --package "{{web_package}}" --platform web "$@"

desktop *args:
    dx serve --package "{{desktop_package}}" --platform desktop "$@"

android *args:
    dx serve --package "{{mobile_package}}" --platform android "$@"

ios *args:
    dx serve --package "{{mobile_package}}" --platform ios "$@"

build: build-console build-node build-web build-desktop build-android

build-console *args:
    cargo build --package "{{console_package}}" "$@"

build-node *args:
    cargo build --package "{{node_package}}" "$@"

build-web *args:
    dx build --package "{{web_package}}" --platform web "$@"

build-desktop *args:
    dx build --package "{{desktop_package}}" --platform desktop "$@"

build-android *args:
    dx build --package "{{mobile_package}}" --platform android "$@"

build-ios *args:
    dx build --package "{{mobile_package}}" --platform ios "$@"

release: release-console release-node release-web release-desktop release-android

release-console *args:
    cargo build --release --package "{{console_package}}" "$@"

release-node *args:
    cargo build --release --package "{{node_package}}" "$@"

release-web *args:
    dx build --release --package "{{web_package}}" --platform web "$@"

release-desktop *args:
    dx build --release --package "{{desktop_package}}" --platform desktop "$@"

release-android *args:
    dx build --release --package "{{mobile_package}}" --platform android "$@"

release-ios *args:
    dx build --release --package "{{mobile_package}}" --platform ios "$@"

check:
    cargo check --workspace

fmt:
    cargo fmt --all
    dx fmt
    prek run --all-files

test:
    cargo nextest run --workspace --all-features

doc:
    cargo doc --workspace --no-deps

license:
    cargo about generate --workspace about.hbs > licenses.html

update: && license
    cargo install-update -a
    cargo update
    cargo deny fetch
    prek autoupdate
    nix flake update
