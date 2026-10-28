default:
    @just --list

install-dev:
    cargo binstall cargo-deny cargo-nextest cargo-update -y --force
    cargo deny fetch

clippy:
    cargo clippy --workspace --all-targets --all-features -- -D warnings

check:
    cargo check --workspace

fmt:
    cargo fmt --all
    pre-commit run --all-files

test:
    cargo nextest run --workspace --all-features

doc:
    cargo doc --workspace --no-deps

update:
    cargo install-update -a
    cargo update
    cargo deny fetch
    pre-commit autoupdate
    nix flake update
