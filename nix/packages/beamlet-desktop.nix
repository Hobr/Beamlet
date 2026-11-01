{
  lib,
  makeRustPlatform,
  rustToolchain,

  pkg-config,
  dioxus-cli,
  wrapGAppsHook3,

  openssl,
  glib,
  gtk3,
  webkitgtk_4_1,
  xdotool,
}:

let
  workspace = (builtins.fromTOML (builtins.readFile ../../Cargo.toml)).workspace.package;
in
(makeRustPlatform {
  cargo = rustToolchain;
  rustc = rustToolchain;
}).buildRustPackage
  {
    pname = "beamlet-desktop";
    inherit (workspace) version;
    src = lib.fileset.toSource {
      root = ../..;
      fileset = lib.fileset.unions [
        ../../Cargo.toml
        ../../Cargo.lock
        ../../apps
      ];
    };
    cargoLock.lockFile = ../../Cargo.lock;

    cargoBuildFlags = [ "--package=beamlet-desktop" ];
    cargoTestFlags = [ "--package=beamlet-desktop" ];

    nativeBuildInputs = [
      pkg-config
      dioxus-cli
      wrapGAppsHook3
    ];
    buildInputs = [
      openssl
      glib
      gtk3
      webkitgtk_4_1
      xdotool
    ];

    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      export CARGO_BUILD_JOBS="$NIX_BUILD_CORES"
      dx build --release --package beamlet-desktop --platform desktop --offline --frozen
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/libexec/beamlet-desktop"
      cp -r target/dx/beamlet-desktop/release/linux/app/. "$out/libexec/beamlet-desktop/"
      runHook postInstall
    '';

    dontWrapGApps = true;
    preFixup = ''
      makeWrapper "$out/libexec/beamlet-desktop/beamlet-desktop" "$out/bin/beamlet-desktop" \
        "''${gappsWrapperArgs[@]}"
    '';

    meta = {
      description = "Beamlet desktop";
      homepage = workspace.repository;
      license = lib.licenses.asl20;
      mainProgram = "beamlet-desktop";
      platforms = lib.platforms.linux;
    };
  }
