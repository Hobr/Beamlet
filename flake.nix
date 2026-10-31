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

      devShell =
        pkgs:
        let
          androidPlatform = "34";
          androidBuildTools = "34.0.0";
          androidNdk = "27.0.12077973";

          androidAbi = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64-v8a" else "x86_64";
          androidJdk = pkgs.jdk17_headless;
          androidSdk = pkgs.androidenv.composeAndroidPackages {
            platformVersions = [ androidPlatform ];
            buildToolsVersions = [ androidBuildTools ];
            toolsVersion = null;
            includeNDK = true;
            ndkVersions = [ androidNdk ];
            includeEmulator = true;
            includeSystemImages = true;
            systemImageTypes = [ "google_apis" ];
            abiVersions = [ androidAbi ];
            includeSources = false;
            includeCmake = false;
          };
        in
        rec {
          packages =
            with pkgs;
            [
              pkg-config
              openssl

              rustToolchain
              cargo-binstall

              androidSdk.androidsdk
              androidJdk

              just
              just-lsp
            ]
            ++ lib.optionals stdenv.hostPlatform.isLinux [
              glib
              gtk3
              webkitgtk_4_1
              xdotool
            ];

          env = with pkgs; rec {
            LD_LIBRARY_PATH = lib.makeLibraryPath packages;
            RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
            ANDROID_HOME = "${androidSdk.androidsdk}/libexec/android-sdk";
            ANDROID_NDK_ROOT = "${ANDROID_HOME}/ndk/${androidNdk}";
            ANDROID_NDK_HOME = ANDROID_NDK_ROOT;
            NDK_HOME = ANDROID_NDK_ROOT;
            JAVA_HOME = "${androidJdk}/lib/openjdk";
          };

          shellHook = ''
            export CARGO_HOME="$PWD/.cargo"
            export PATH="$CARGO_HOME/bin:$PWD/target/debug:$PATH"
            export GRADLE_OPTS="''${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.project.android.aapt2FromMavenOverride=$ANDROID_HOME/build-tools/${androidBuildTools}/aapt2"
          '';
        };
    };
}
