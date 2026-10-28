# Home Manager module for claude-pod.
#
# Usage, once this flake is added to your home-manager config's inputs and
# this module is imported:
#
#   programs.claude-pod.enable = true;
#
{ self }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.claude-pod;
in
{
  options.programs.claude-pod = {
    enable = lib.mkEnableOption "claude-pod, an ephemeral Podman sandbox for Claude Code";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.default;
      defaultText = lib.literalExpression "claude-pod.packages.<system>.default";
      description = "The claude-pod package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
