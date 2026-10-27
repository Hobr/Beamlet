{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flakelight.url = "github:nix-community/flakelight";
  };

  outputs =
    { flakelight, ... }@inputs:
    flakelight ./. {
      inherit inputs;

      devShell = pkgs: {
        packages = with pkgs; [
          go_latest

          gopls
          gotools
          golangci-lint
          govulncheck
          go-tools
          nilaway
          errcheck
          panicparse
          delve

          pre-commit
        ];

        env = {
          GO111MODULE = "on";
          GOPROXY = "https://goproxy.cn";
        };
      };

      packages = pkgs: {
        server = pkgs.buildGoModule {
          src = ./.;
          vendorHash = null;
          subPackages = [ "cmd/server" ];
        };
      };
    };
}
