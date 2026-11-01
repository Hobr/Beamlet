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

      nixpkgs.config = {
        allowUnfree = true;
        android_sdk.accept_license = true;
      };

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

                  "aarch64-linux-android"
                  "i686-linux-android"
                  "armv7-linux-androideabi"
                  "x86_64-linux-android"

                  "x86_64-apple-ios"
                  "aarch64-apple-ios"
                  "aarch64-apple-ios-sim"
                  "aarch64-apple-darwin"
                ];
              };
        })
      ];
    };
}
