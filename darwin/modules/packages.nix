{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    bash
    curl
    git
    jq
    ripgrep
  ];
}

