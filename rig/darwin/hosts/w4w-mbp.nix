{ config, pkgs, ... }:

{
  imports = [
    ../modules/macos-defaults.nix
    ../modules/packages.nix
  ];

  system.stateVersion = 6;
  system.primaryUser = "ww";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Determinate Nix owns nix.conf; do not let nix-darwin manage it.
  nix.enable = false;

  networking.hostName = "w4w-mbp";
  networking.computerName = "w4w-mbp";
  networking.localHostName = "w4w-mbp";

  security.pam.services.sudo_local.touchIdAuth = true;

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
