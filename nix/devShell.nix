pkgs: {
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

    go-task
    prek
  ];

  env = {
    GO111MODULE = "on";
    GOPROXY = "https://goproxy.cn";
  };
}
