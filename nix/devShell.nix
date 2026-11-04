pkgs: rec {
  packages = with pkgs; [
    pkg-config
    mold

    rustToolchain
    mold
    cargo-binstall

    flutter
    dart

    just
    just-lsp

    samply
    heaptrack
  ];

  env = with pkgs; rec {
    LD_LIBRARY_PATH = lib.makeLibraryPath packages;
    RUST_SRC_PATH = "${rustToolchain}/lib/rustlib/src/rust/library";
  };

  shellHook = ''
    export CARGO_HOME="$PWD/.cargo"
    export PATH="$CARGO_HOME/bin:$PWD/target/debug:$PATH"
  '';
}
