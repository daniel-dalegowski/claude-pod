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
      default = pkgs.callPackage ./nix/package.nix { };
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
    homeModules.default = import ./nix/module.nix;
    homeManagerModules.default = self.homeModules.default;
  };
}
