{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flakelight.url = "github:nix-community/flakelight";
  };

  outputs =
    { flakelight, ... }@inputs:
    flakelight ./. {
      inherit inputs;

      withOverlays = [
        inputs.rust-overlay.overlays.default

        (final: prev: {
          rustToolchain =
            let
              rust = prev.rust-bin;
            in
            if builtins.pathExists ./rust-toolchain.toml then
              rust.fromRustupToolchainFile ./rust-toolchain.toml

            else if builtins.pathExists ./rust-toolchain then
              rust.fromRustupToolchainFile ./rust-toolchain

            else
              rust.stable."1.99.1".default.override {
                extensions = [
                  "rust-src"
                  "rustfmt"
                  "rust-analyzer"
                  "clippy"
                  "cargo"
                  "llvm-tools"
                ];

                targets = [
                  "wasm32-unknown-unknown"
                ];
              };
        })
      ];

      devShell =
        pkgs: with pkgs; rec {
          packages = [
            pkg-config
            fontconfig
            openssl

            rustToolchain
            cargo-binstall
            pre-commit

            just
            just-lsp
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            glib
            gtk3
            webkitgtk_4_1
            xdotool
          ];

          env = {
            LD_LIBRARY_PATH = lib.makeLibraryPath packages;
            RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
          };

          shellHook = ''
            export CARGO_HOME="$PWD/.cargo"
            export PATH="$CARGO_HOME/bin:$PWD/target/debug:$PATH"
          '';
        };
    };
}
