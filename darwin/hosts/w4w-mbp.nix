{ config, pkgs, ... }:

{
  imports = [
    ../modules/macos-defaults.nix
    ../modules/packages.nix
  ];

  system.stateVersion = 6;
  nixpkgs.hostPlatform = "aarch64-darwin";

  users.users.ww = {
    home = "/Users/ww";
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.ww = {
    home.stateVersion = "25.11";
    programs.home-manager.enable = true;
  };
}
