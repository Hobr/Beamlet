pkgs: {
  packages = with pkgs; [
    go_latest
    golangci-lint
    prek
    go-task
  ];

  env = {
    GO111MODULE = "on";
    GOPROXY = "https://goproxy.cn";
  };

  shellHook = ''
    export PATH="$(go env GOBIN):$PATH"
  '';
}
