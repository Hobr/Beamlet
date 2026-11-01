{
  lib,
  makeRustPlatform,
  rustToolchain,
}:

let
  workspace = (builtins.fromTOML (builtins.readFile ../../Cargo.toml)).workspace.package;
in
(makeRustPlatform {
  cargo = rustToolchain;
  rustc = rustToolchain;
}).buildRustPackage
  {
    pname = "beamlet-node";
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

    cargoBuildFlags = [ "--package=beamlet-node" ];
    cargoTestFlags = [ "--package=beamlet-node" ];

    nativeBuildInputs = [ ];
    buildInputs = [ ];

    meta = {
      description = "Beamlet node";
      homepage = workspace.repository;
      license = lib.licenses.asl20;
      mainProgram = "beamlet-node";
      platforms = lib.platforms.unix;
    };
  }
