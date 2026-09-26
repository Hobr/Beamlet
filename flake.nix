{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flakelight.url = "github:nix-community/flakelight";
  };

  outputs =
    { flakelight, ... }@inputs:
    flakelight ./. {
      inherit inputs;

      devShell =
        pkgs:
        let
          otpVersion = "29";
          elixirVersion = "1_20";
          beam = pkgs."beamMinimal${otpVersion}Packages";
          elixir = beam."elixir_${elixirVersion}";
        in
        {
          packages =
            (with pkgs; [
            ])
            ++ (with beam; [
              elixir
              erlang
              expert
            ]);

          shellHook = ''
            export MIX_HOME="$PWD/.nix-mix"
            export HEX_HOME="$PWD/.nix-hex"
            export MIX_ARCHIVES="$MIX_HOME/archives"
            export PATH="$MIX_HOME/bin:$PATH"

            mkdir -p "$MIX_HOME" "$HEX_HOME"
            export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_file_bytes 1024000"
          '';
        };
    };
}
