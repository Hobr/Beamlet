default:
    @just --list

install-dev:
    cargo binstall cargo-deny cargo-nextest cargo-update cargo-about -y --force
    cargo deny fetch

check:
    cargo check --workspace

fmt:
    cargo fmt --all
    pre-commit run --all-files

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
    pre-commit autoupdate
    nix flake update
