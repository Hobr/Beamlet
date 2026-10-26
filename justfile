default:
    @just --list

install-dev:
    cargo binstall cargo-deny cargo-nextest cargo-update cargo-llvm-cov wasmtime-cli wasm-tools -y --force
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

coverage:
    cargo llvm-cov nextest --workspace --html

doc:
    cargo doc --workspace --no-deps

update:
    nix flake update
    cargo install-update -a
    cargo update
    pre-commit autoupdate
    cargo deny fetch
