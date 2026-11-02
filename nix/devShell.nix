pkgs: {
  packages = with pkgs; [
    go_latest
    golangci-lint

    prek
    go-task

    nats-server
    natscli
    nats-top
  ];

  env = {
    GO111MODULE = "on";
    GOPROXY = "https://goproxy.cn";
  };

  shellHook = ''
    export PATH="$(go env GOBIN):$PATH"
  '';
}
