{
  lib,
  makeRustPlatform,
  rustToolchain,

  pkg-config,
}:

let
  workspace = (builtins.fromTOML (builtins.readFile ../../Cargo.toml)).workspace.package;
in
(makeRustPlatform {
  cargo = rustToolchain;
  rustc = rustToolchain;
}).buildRustPackage
  {
    pname = "beamlet-console";
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

    cargoBuildFlags = [ "--package=beamlet-console" ];
    cargoTestFlags = [ "--package=beamlet-console" ];

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ ];

    meta = {
      description = "Beamlet console";
      homepage = workspace.repository;
      license = lib.licenses.asl20;
      mainProgram = "beamlet-console";
      platforms = lib.platforms.unix;
    };
  }
