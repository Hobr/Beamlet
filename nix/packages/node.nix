{ buildGoLatestModule }:
buildGoLatestModule {
  name = "beamlet-node";

  src = ../../.;
  subPackages = [ "cmd/node" ];
  vendorHash = null;

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-extldflags '-static'"
  ];
}
