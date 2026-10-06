{ pkgs, lib, ... }:

{
  programs.firefox = lib.mkMerge [
    (import ./common.nix { inherit pkgs; })
    {
      enable = false;
      package = pkgs.firefox;
    }
  ];
}
