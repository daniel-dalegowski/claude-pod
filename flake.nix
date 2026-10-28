{
  description = "claude-pod — ephemeral Podman sandbox for a single project directory";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.stdenv.mkDerivation {
        pname = "claude-pod";
        version = pkgs.lib.fileContents ./VERSION;
        src = ./.;

        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall

          datadir="$out/share/claude-pod"
          install -Dm644 Containerfile       "$datadir/Containerfile"
          install -Dm644 container-xdg-open  "$datadir/container-xdg-open"
          install -Dm644 container-claude.md "$datadir/container-claude.md"
          install -Dm644 VERSION             "$datadir/VERSION"
          install -Dm644 agents/debugger.md  "$datadir/agents/debugger.md"
          install -Dm644 agents/architect.md "$datadir/agents/architect.md"

          install -Dm755 claude-pod "$out/bin/claude-pod"
          # Replace the runtime self-location with the fixed Nix store path so
          # 'podman build' finds the Containerfile and COPY sources correctly.
          sed -i "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\"$datadir\"|" "$out/bin/claude-pod"

          runHook postInstall
        '';

        meta = with pkgs.lib; {
          description = "Ephemeral Podman sandbox for a single project directory";
          mainProgram = "claude-pod";
          platforms = [ "x86_64-linux" "aarch64-linux" ];
        };
      };
    });

    apps = forAllSystems (system: {
      default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/claude-pod";
      };
    });

    # Home Manager module — lets a home.nix enable claude-pod declaratively:
    #   programs.claude-pod.enable = true;
    # instead of manually adding the flake's package output to home.packages.
    homeModules.default = import ./nix/module.nix { inherit self; };
    homeManagerModules.default = self.homeModules.default;
  };
}
