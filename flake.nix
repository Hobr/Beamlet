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

          mage
          pre-commit
        ];

        env = {
          GO111MODULE = "on";
          GOPROXY = "https://goproxy.cn";
        };

        shellHook = ''
          export PATH="$HOME/go/bin:$PATH"
        '';
      };

      packages.server =
        pkgs:
        pkgs.buildGoModule {
          src = ./.;
          vendorHash = null;
          subPackages = [ "cmd/server" ];
        };
    };
}
