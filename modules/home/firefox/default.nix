{ pkgs, lib, ... }:

{
  programs.firefox = lib.mkMerge [
    (import ./common.nix { inherit pkgs; })
    {
      enable = true;
      package = pkgs.firefox;
    }
  ];
}
