pkgs: {
  packages = with pkgs; [
    go_latest
    golangci-lint

    prek
    go-task

    nats-server
    natscli
    nats-top

    kubectl
    k9s
    kind

    (wrapHelm kubernetes-helm {
      plugins = with pkgs.kubernetes-helmPlugins; [
        helm-diff
        helm-unittest
        helm-secrets
        helm-git
        helm-dt
        helm-schema
      ];
    })
  ];

  env = {
    GO111MODULE = "on";
    GOPROXY = "https://goproxy.cn";
  };

  shellHook = ''
    export PATH="$(go env GOBIN):$PATH"
  '';
}
