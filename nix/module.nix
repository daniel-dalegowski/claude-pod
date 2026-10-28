# Home Manager module for claude-pod.
#
# Usage, in a home-manager config:
#
#   imports = [ /path/to/claude-pod/nix/module.nix ];
#   programs.claude-pod.enable = true;
#
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.claude-pod;
in
{
  options.programs.claude-pod = {
    enable = lib.mkEnableOption "claude-pod, an ephemeral Podman sandbox for Claude Code";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      description = "The claude-pod package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
