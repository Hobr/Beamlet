{ buildGoModule }:
buildGoModule {
  src = ../../.;
  vendorHash = null;
  subPackages = [ "cmd/node" ];
}
